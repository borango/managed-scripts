#!/usr/bin/env bash
# clone-pi-sd.sh — Clone a Raspberry Pi OS SD card to a (potentially smaller) card.
#
# Preserves the MBR disk identifier (so PARTUUIDs in fstab/cmdline.txt remain valid),
# filesystem UUIDs, and all metadata.  The destination root partition is expanded to
# fill the available space on the target card.
#
# Source can be REMOTE (read over SSH) or LOCAL (a card reader attached to this machine).
#
# Usage:
#   Remote:  clone-pi-sd.sh HOST:/dev/mmcblk0 /dev/sdb
#   Local:   clone-pi-sd.sh /dev/mmcblk0      /dev/sdb
#
# The HOST:/dev/... syntax mirrors scp/rsync convention.  The remote user is $USER.
# Both device paths must be whole-disk block devices (e.g. /dev/sdb, /dev/mmcblk0),
# not partitions (/dev/sdb1) or mount points (/mnt/foo).
#
# Requirements (local):  rsync, sfdisk, partprobe, mkfs.ext4, e2fsck, blkid, dd, findmnt
# Requirements (remote): passwordless sudo on the source host for sfdisk, blkid, dd, rsync

set -euo pipefail

PROG=$(basename "$0")

# ── Defaults ────────────────────────────────────────────────────────────────
SOURCE_HOST=""
SOURCE_DEV=""
DEST_DEV=""
DEST_MOUNT="/mnt/pi_dest"
SRC_MOUNT="/mnt/pi_src"

# sudo rsync runs as root and cannot find $USER's key on its own; derive it here
# while $HOME still points at the invoking user's directory.
SSH_KEY="$HOME/.ssh/id_rsa"

# ── Usage ────────────────────────────────────────────────────────────────────
# Detect the local boot disk and any USB block devices.
# Populates globals: DETECTED_SRC, DETECTED_SRC_USED, DETECTED_DESTS (array)
DETECTED_SRC=""
DETECTED_SRC_USED=""
DETECTED_DESTS=()

autodetect() {
    local root_part src_disk
    root_part=$(findmnt -n -o SOURCE / 2>/dev/null)       || return 0
    src_disk=$(lsblk -no PKNAME "$root_part" 2>/dev/null) || return 0
    [[ -z "$src_disk" ]] && return 0
    DETECTED_SRC="/dev/$src_disk"
    DETECTED_SRC_USED=$(df -h / 2>/dev/null | awk 'NR==2{print $3}')

    local usb_disks dest
    usb_disks=$(lsblk -d -o NAME,TRAN 2>/dev/null | awk '$2=="usb"{print "/dev/"$1}')
    while IFS= read -r dest; do
        [[ -b "$dest" ]] || continue
        DETECTED_DESTS+=("$dest")
    done <<< "$usb_disks"
}

autodetect

usage() {
    local src="${DETECTED_SRC:-/dev/mmcblk0}"
    local dest="${DETECTED_DESTS[0]:-/dev/sdb}"

    cat >&2 <<EOF
Usage:
  Remote source: $PROG HOST:${src} ${dest}
  Local source:  $PROG ${src} ${dest}

Arguments:
  SOURCE          Source device, optionally prefixed with HOST: for remote
                    Remote: bridge:/dev/mmcblk0   (SSH login as \$USER)
                    Local:  /dev/mmcblk0
                  Must be a whole-disk device, not a partition or mount point.
  DEST            Destination whole-disk block device  (e.g. /dev/sdb, not /dev/sdb1)

Options:
  --dest-mount    Dest root mount point                (default: /mnt/pi_dest)
  --src-mount     Source root mount point              (default: /mnt/pi_src, local only)
EOF

    if [[ -n "$DETECTED_SRC" && ${#DETECTED_DESTS[@]} -gt 0 ]]; then
        echo >&2
        echo "Detected on this machine:" >&2
        echo "  Boot disk (source) : $DETECTED_SRC  [${DETECTED_SRC_USED} used]" >&2
        for dest in "${DETECTED_DESTS[@]}"; do
            local size
            size=$(lsblk -dno SIZE "$dest" 2>/dev/null)
            echo "  USB disk  (dest)   : $dest  [$size]" >&2
        done
    fi

    exit 1
}

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest-mount)  DEST_MOUNT="$2"; shift 2 ;;
        --src-mount)   SRC_MOUNT="$2";  shift 2 ;;
        -h|--help)     usage ;;
        -*) echo "$PROG: unknown option: $1" >&2; usage ;;
        *)  break ;;
    esac
done

[[ $# -lt 2 ]] && { echo "$PROG: SOURCE and DEST arguments are required" >&2; usage; }
[[ $# -gt 2 ]] && { echo "$PROG: too many arguments" >&2; usage; }

SOURCE_ARG="$1"
DEST_DEV="$2"

# ── Parse HOST:DEVICE from SOURCE ───────────────────────────────────────────
if [[ "$SOURCE_ARG" == *:* ]]; then
    SOURCE_HOST="${SOURCE_ARG%%:*}"
    SOURCE_DEV="${SOURCE_ARG#*:}"
else
    SOURCE_HOST=""
    SOURCE_DEV="$SOURCE_ARG"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
log() { echo; echo "==> $*"; }
die() { echo "$PROG: error: $*" >&2; exit 1; }

# ── Validate that arguments are whole-disk block devices ─────────────────────

# Reject partition-like suffixes.
# mmcblk/nvme whole disks end in a digit (mmcblk0, nvme0n1) — only their p-suffixed
# children are partitions.  For sd-style disks the whole disk ends in a letter (sda,
# sdb) so any trailing digit indicates a partition.
is_partition() {
    local dev
    dev=$(basename "$1")
    if [[ "$dev" =~ ^(mmcblk|nvme) ]]; then
        [[ "$dev" =~ p[0-9]+$ ]]
    else
        [[ "$dev" =~ [0-9]+$ ]]
    fi
}

# Check whether a path is a block device (local check only)
assert_block_device() {
    local label="$1" path="$2"
    if is_partition "$path"; then
        die "${label^^} looks like a partition ($(basename "$path")); supply the whole-disk device instead"
    fi
    if [[ ! -b "$path" ]]; then
        die "--${label} $path is not a block device"
    fi
    # Confirm it has no partition number in its own name and lsblk sees it as a disk
    local type
    type=$(lsblk -dno TYPE "$path" 2>/dev/null || true)
    if [[ "$type" != "disk" ]]; then
        die "--${label} $path is not a whole disk (lsblk type: '${type:-unknown}'); use the parent disk device"
    fi
}

# Source device: block-device check is only possible locally
if [[ -z "$SOURCE_HOST" ]]; then
    assert_block_device "source" "$SOURCE_DEV"
else
    # For remote source, at minimum reject obvious partition suffixes
    if is_partition "$SOURCE_DEV"; then
        die "SOURCE looks like a partition ($(basename "$SOURCE_DEV")); supply the whole-disk device instead"
    fi
fi

assert_block_device "dest" "$DEST_DEV"

[[ "$SOURCE_DEV" == "$DEST_DEV" ]] && { echo "$PROG: SOURCE and DEST are the same device" >&2; exit 1; }

# ── Helpers ──────────────────────────────────────────────────────────────────

# Derive partition device name: mmcblk/nvme use a 'p' suffix, others don't.
part_name() {
    local dev="$1" n="$2"
    [[ "$dev" =~ (mmcblk|nvme) ]] && echo "${dev}p${n}" || echo "${dev}${n}"
}

SRC_P1=$(part_name "$SOURCE_DEV" 1)
SRC_P2=$(part_name "$SOURCE_DEV" 2)
DEST_P1=$(part_name "$DEST_DEV" 1)
DEST_P2=$(part_name "$DEST_DEV" 2)

# Run a privileged command on the source — via SSH or locally.
src_cmd() {
    if [[ -n "$SOURCE_HOST" ]]; then
        local remote_cmd="sudo"
        for arg in "$@"; do
            remote_cmd+=" $(printf '%q' "$arg")"
        done
        ssh -o StrictHostKeyChecking=no "$USER@$SOURCE_HOST" "$remote_cmd"
    else
        sudo "$@"
    fi
}

# Best-effort unmount and removal of mount points on exit/error
cleanup() {
    sudo umount "${DEST_MOUNT}/boot/firmware" 2>/dev/null || true
    sudo umount "$DEST_MOUNT"                 2>/dev/null || true
    sudo umount "$SRC_MOUNT"                  2>/dev/null || true
    sudo rmdir  "${DEST_MOUNT}/boot/firmware" 2>/dev/null || true
    sudo rmdir  "$DEST_MOUNT"                 2>/dev/null || true
    sudo rmdir  "$SRC_MOUNT"                  2>/dev/null || true
}
trap cleanup EXIT

# ── Safety prompt ────────────────────────────────────────────────────────────
echo
echo "  Source : ${SOURCE_DEV}${SOURCE_HOST:+ on ${SOURCE_HOST}}"
echo "  Dest   : ${DEST_DEV} (will be OVERWRITTEN)"
echo
read -r -p "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ════════════════════════════════════════════════════════════════════════════
# Phase 0 — Gather source info
# ════════════════════════════════════════════════════════════════════════════
log "Phase 0: Gathering source partition info from $SOURCE_DEV"

SFDISK_DUMP=$(src_cmd sfdisk -d "$SOURCE_DEV")
echo "$SFDISK_DUMP"

UUID_P1=$(src_cmd blkid -s UUID -o value "$SRC_P1")
UUID_P2=$(src_cmd blkid -s UUID -o value "$SRC_P2")
log "  Boot partition UUID : $UUID_P1"
log "  Root partition UUID : $UUID_P2"

# ════════════════════════════════════════════════════════════════════════════
# Phase 1 — Partition destination
# ════════════════════════════════════════════════════════════════════════════
log "Phase 1: Partitioning $DEST_DEV"

# Unmount any partitions currently mounted from the dest device
while IFS= read -r part; do
    local_part="/dev/${part}"
    mnt=$(findmnt -n -o TARGET "$local_part" 2>/dev/null || true)
    if [[ -n "$mnt" ]]; then
        log "  Unmounting $local_part (mounted at $mnt)"
        sudo umount "$local_part"
    fi
done < <(lsblk -lno NAME "$DEST_DEV" | tail -n +2)

# Apply a modified partition table to the destination:
#   - strip last-lba so sfdisk uses the dest card's full size
#   - rename source device paths to dest device paths
#   - remove the explicit size on p2 so it expands to fill remaining space
echo "$SFDISK_DUMP" \
    | sed '/last-lba/d' \
    | sed "s|${SRC_P1}|${DEST_P1}|g; \
           s|${SRC_P2}|${DEST_P2}|g; \
           s|device: ${SOURCE_DEV}|device: ${DEST_DEV}|g" \
    | sed "/$(basename "$DEST_P2")/s/size=[^,]*, //" \
    | sudo sfdisk --no-reread "$DEST_DEV"

sudo partprobe "$DEST_DEV"
sleep 1

log "New layout on $DEST_DEV:"
lsblk -o NAME,SIZE,FSTYPE "$DEST_DEV"

# ════════════════════════════════════════════════════════════════════════════
# Phase 2 — Copy boot partition (block-level via dd)
# ════════════════════════════════════════════════════════════════════════════
log "Phase 2: Copying boot partition ($SRC_P1 → $DEST_P1)"

if [[ -n "$SOURCE_HOST" ]]; then
    ssh -o StrictHostKeyChecking=no "$USER@$SOURCE_HOST" \
        "sudo dd if=${SRC_P1} bs=4M status=progress" \
        | sudo dd of="$DEST_P1" bs=4M
else
    sudo dd if="$SRC_P1" of="$DEST_P1" bs=4M status=progress
fi

# ════════════════════════════════════════════════════════════════════════════
# Phase 3 — Copy root filesystem (rsync)
# ════════════════════════════════════════════════════════════════════════════
log "Phase 3a: Formatting $DEST_P2 as ext4 (UUID=$UUID_P2)"
sudo mkfs.ext4 -U "$UUID_P2" "$DEST_P2"

log "Phase 3b: Mounting $DEST_P2 → $DEST_MOUNT"
sudo mkdir -p "$DEST_MOUNT"
sudo mount "$DEST_P2" "$DEST_MOUNT"

log "Phase 3c: Syncing root filesystem"

RSYNC_OPTS=(
    -axAX
    --info=progress2
    --exclude=/proc
    --exclude=/sys
    --exclude=/dev
    --exclude=/run
    --exclude=/tmp
    --exclude=/boot/firmware
    --exclude=/var/swap                      # recreated on first boot by dphys-swapfile
    --exclude=/var/lib/systemd/random-seed  # new seed written on every boot
)

if [[ -n "$SOURCE_HOST" ]]; then
    # Remote: rsync pulls from the live system over SSH.
    # --rsync-path="sudo rsync" gives access to all files on the remote side.
    sudo rsync "${RSYNC_OPTS[@]}" \
        -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
        --rsync-path="sudo rsync" \
        "$USER@${SOURCE_HOST}:/" "${DEST_MOUNT}/"
else
    # Local: two sub-cases depending on whether the source is the live running system.
    live_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null)
    if [[ "/dev/$live_disk" == "$SOURCE_DEV" ]]; then
        # Source is the running OS — root is already mounted, rsync directly from /.
        log "  Source is the live system, rsyncing from /"
        sudo rsync "${RSYNC_OPTS[@]}" / "${DEST_MOUNT}/"
    else
        # Source is an offline external card — mount it first.
        # /boot/firmware on the source p2 is an empty mountpoint dir (separate partition),
        # so the exclude is safe and we rely on the dd copy from Phase 2.
        log "  Mounting source $SRC_P2 → $SRC_MOUNT (read-only)"
        sudo mkdir -p "$SRC_MOUNT"
        sudo mount -o ro "$SRC_P2" "$SRC_MOUNT"

        sudo rsync "${RSYNC_OPTS[@]}" "${SRC_MOUNT}/" "${DEST_MOUNT}/"

        sudo umount "$SRC_MOUNT"
        sudo rmdir  "$SRC_MOUNT"
    fi
fi

log "Phase 3d: Creating excluded virtual-fs mountpoint directories"
sudo mkdir -p "${DEST_MOUNT}"/{proc,sys,dev,run,tmp,boot/firmware}

log "Phase 3e: Unmounting $DEST_MOUNT"
sudo umount "$DEST_MOUNT"
sudo rmdir  "$DEST_MOUNT"

# ════════════════════════════════════════════════════════════════════════════
# Phase 4 — Verify
# ════════════════════════════════════════════════════════════════════════════
log "Phase 4: Verifying clone"

log "  e2fsck on $DEST_P2"
sudo e2fsck -fy "$DEST_P2"

log "  Partition layout:"
lsblk -o NAME,SIZE,FSTYPE,UUID "$DEST_DEV"

log "  Inspecting boot config"
sudo mkdir -p "$DEST_MOUNT"
sudo mount "$DEST_P2" "$DEST_MOUNT"
sudo mount "$DEST_P1" "${DEST_MOUNT}/boot/firmware"

echo
echo "  /etc/fstab:"
cat "${DEST_MOUNT}/etc/fstab"
echo
echo "  cmdline.txt:"
cat "${DEST_MOUNT}/boot/firmware/cmdline.txt"

sudo umount "${DEST_MOUNT}/boot/firmware"
sudo umount "$DEST_MOUNT"
sudo rmdir  "$DEST_MOUNT"

log "Clone complete:  $SOURCE_DEV${SOURCE_HOST:+ on ${SOURCE_HOST}}  →  $DEST_DEV"
