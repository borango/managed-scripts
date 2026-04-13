#!/usr/bin/env bash
# cleanup.sh — find and remove safely removable large files on Debian/Ubuntu Linux
# Usage: sudo ./cleanup.sh [--dry-run] [--yes]
#   --dry-run   Show what would be removed, make no changes
#   --yes       Skip per-category confirmation prompts (still requires sudo)

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}▸ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
success() { echo -e "${GREEN}✔ $*${RESET}"; }
header()  { echo -e "\n${BOLD}━━ $* ━━${RESET}"; }
size_of() { du -sh "$@" 2>/dev/null | cut -f1; }

# ── Args ──────────────────────────────────────────────────────────────────────
DRY_RUN=false
AUTO_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes)     AUTO_YES=true ;;
    -h|--help)
      echo "Usage: sudo $0 [--dry-run] [--yes]"
      echo "  --dry-run  Show sizes only, change nothing"
      echo "  --yes      Auto-confirm all safe categories"
      exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

[[ $EUID -ne 0 ]] && { warn "Most cleanups need root. Re-run with sudo."; }

FREED_TOTAL=0  # bytes (best-effort running tally via du)

# ── Prompt helper ─────────────────────────────────────────────────────────────
# ask <description> <size>  → returns 0 if user wants to proceed
ask() {
  local desc="$1" sz="$2"
  if $DRY_RUN; then
    echo -e "  [dry-run] Would free ~${YELLOW}${sz}${RESET}: ${desc}"
    return 1   # don't actually run the action
  fi
  if $AUTO_YES; then
    echo -e "  ${GREEN}Auto-yes${RESET}: freeing ~${YELLOW}${sz}${RESET} — ${desc}"
    return 0
  fi
  echo -e "  Free ~${YELLOW}${sz}${RESET}: ${desc}"
  read -r -p "  Proceed? [y/N] " ans
  [[ "${ans,,}" == y* ]]
}

# ── 1. systemd journal ────────────────────────────────────────────────────────
header "systemd journal"
if command -v journalctl &>/dev/null; then
  JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | awk '/take up/{print $7, $8}' || echo "?")
  info "Current journal usage: $JOURNAL_SIZE"
  info "Keeping last 7 days / max 200 MB"
  if ask "vacuum systemd journal (keep 7 days, max 200 MB)" "$JOURNAL_SIZE"; then
    journalctl --vacuum-time=7d --vacuum-size=200M
    success "Journal vacuumed"
  fi
else
  warn "journalctl not found, skipping"
fi

# ── 2. apt / dpkg package cache ───────────────────────────────────────────────
header "apt package cache"
if command -v apt-get &>/dev/null; then
  APT_CACHE=$(size_of /var/cache/apt/archives/)
  info "apt cache: $APT_CACHE"
  if ask "apt-get clean (remove all cached .deb files)" "$APT_CACHE"; then
    apt-get clean
    success "apt cache cleared"
  fi
  # Autoremove unused packages
  AUTOREMOVE_LIST=$(apt-get --dry-run autoremove 2>/dev/null | grep "^Remv" || true)
  if [[ -n "$AUTOREMOVE_LIST" ]]; then
    COUNT=$(echo "$AUTOREMOVE_LIST" | wc -l)
    if ask "apt-get autoremove ($COUNT unused packages)" "${COUNT} pkgs"; then
      apt-get -y autoremove
      success "Unused packages removed"
    fi
  else
    info "No unused packages to autoremove"
  fi
fi

# ── 3. apt-cacher-ng proxy cache ──────────────────────────────────────────────
header "apt-cacher-ng proxy cache"
ACNG_DIR="/var/cache/apt-cacher-ng"
if [[ -d "$ACNG_DIR" ]]; then
  ACNG_SIZE=$(size_of "$ACNG_DIR")
  info "apt-cacher-ng cache: $ACNG_SIZE"
  warn "This is a local apt proxy cache. Safe to clear — packages re-downloaded on next use."
  if ask "remove all apt-cacher-ng cached packages" "$ACNG_SIZE"; then
    # Preferred: use the built-in expiry tool if available
    if command -v apt-cacher-ng &>/dev/null || [[ -f /usr/sbin/apt-cacher-ng ]]; then
      # Stop service, wipe, restart
      systemctl stop apt-cacher-ng 2>/dev/null || true
      find "$ACNG_DIR" -type f \( -name "*.deb" -o -name "*.gz" -o -name "*.xz" \
           -o -name "*.bz2" -o -name "*.lzma" -o -name "*.dsc" \) -delete
      systemctl start apt-cacher-ng 2>/dev/null || true
    else
      find "$ACNG_DIR" -type f -delete
    fi
    success "apt-cacher-ng cache cleared ($(size_of "$ACNG_DIR") remaining metadata)"
  fi
else
  info "apt-cacher-ng not present, skipping"
fi

# ── 4. Old kernel packages ────────────────────────────────────────────────────
header "old kernel packages"
if command -v dpkg &>/dev/null; then
  CURRENT_KERNEL=$(uname -r)
  # List installed linux-image packages that are NOT the running kernel
  OLD_KERNELS=$(dpkg -l 'linux-image-*' 2>/dev/null \
    | awk '/^ii/ {print $2}' \
    | grep -v "$CURRENT_KERNEL" \
    | grep -v 'linux-image-amd64\|linux-image-arm64\|linux-image-generic\|linux-image-virtual' \
    || true)
  if [[ -n "$OLD_KERNELS" ]]; then
    COUNT=$(echo "$OLD_KERNELS" | wc -l)
    # Sum installed sizes (dpkg reports in KiB)
    KERNEL_KB=$(dpkg-query -Wf '${Package}\t${Installed-Size}\n' linux-image-\* 2>/dev/null \
      | grep -Ff <(echo "$OLD_KERNELS") \
      | awk '{sum+=$2} END{print sum}')
    KERNEL_SIZE="~$((KERNEL_KB/1024)) MB"
    info "Running kernel: $CURRENT_KERNEL"
    echo "$OLD_KERNELS" | sed 's/^/    /'
    if ask "remove $COUNT old kernel package(s)" "$KERNEL_SIZE"; then
      # shellcheck disable=SC2086
      apt-get -y purge $OLD_KERNELS
      apt-get -y autoremove
      success "Old kernels removed"
    fi
  else
    info "No old kernel packages found"
  fi
fi

# ── 5. Thumbnail / user caches ────────────────────────────────────────────────
header "user caches"
# Run as the invoking non-root user when possible
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

for CACHE_DIR in \
    "$REAL_HOME/.cache/thumbnails" \
    "$REAL_HOME/.thumbnails" \
    "$REAL_HOME/.cache/pip" \
    "$REAL_HOME/.cache/npm" \
    "$REAL_HOME/.cache/yarn" \
    "$REAL_HOME/.cache/go/download" \
    "$REAL_HOME/.cache/mozilla/firefox" \
    "$REAL_HOME/.cache/chromium" \
    "$REAL_HOME/.cache/google-chrome"
do
  [[ -d "$CACHE_DIR" ]] || continue
  SZ=$(size_of "$CACHE_DIR")
  if ask "remove $CACHE_DIR" "$SZ"; then
    rm -rf "$CACHE_DIR"
    success "Removed $CACHE_DIR"
  fi
done

# ── 6. User Trash ─────────────────────────────────────────────────────────────
header "Trash"
TRASH_DIR="$REAL_HOME/.local/share/Trash"
if [[ -d "$TRASH_DIR" ]]; then
  TRASH_SIZE=$(size_of "$TRASH_DIR")
  if ask "empty Trash ($TRASH_DIR)" "$TRASH_SIZE"; then
    rm -rf "${TRASH_DIR:?}/files/"* "${TRASH_DIR:?}/info/"* 2>/dev/null || true
    success "Trash emptied"
  fi
else
  info "Trash directory not found"
fi

# ── 7. /tmp and /var/tmp old files ───────────────────────────────────────────
header "/tmp and /var/tmp"
TMP_OLD=$(find /tmp /var/tmp -maxdepth 1 -mindepth 1 -atime +7 2>/dev/null | wc -l)
if [[ $TMP_OLD -gt 0 ]]; then
  if ask "delete $TMP_OLD files/dirs in /tmp and /var/tmp not accessed in 7+ days" "${TMP_OLD} items"; then
    find /tmp /var/tmp -maxdepth 1 -mindepth 1 -atime +7 -exec rm -rf {} + 2>/dev/null || true
    success "Old temp files removed"
  fi
else
  info "No stale temp files (>7 days old) found"
fi

# ── 8. Core dumps ─────────────────────────────────────────────────────────────
header "core dumps"
# -type f; exclude compressed files, system paths, and container overlay filesystems
CORES=$(find / -xdev -type f \( -name "core" -o -name "core.[0-9]*" \) \
  ! -name "*.gz" ! -name "*.xz" ! -name "*.bz2" ! -name "*.js" \
  ! -name "*.js.map" ! -name "*.js.br" \
  ! -path "/usr/*" ! -path "/proc/*" \
  ! -path "/var/lib/docker/*" ! -path "/var/lib/containerd/*" \
  2>/dev/null | head -50)
SYSTEMD_CORE_DIR="/var/lib/systemd/coredump"
SYSTEMD_CORES=$(find "$SYSTEMD_CORE_DIR" -type f 2>/dev/null)
ALL_CORES=$(printf '%s\n%s\n' "$CORES" "$SYSTEMD_CORES" | grep -v '^$' || true)
if [[ -n "$ALL_CORES" ]]; then
  CORE_COUNT=$(echo "$ALL_CORES" | wc -l)
  CORE_KB=$(echo "$ALL_CORES" | xargs -r du -sk 2>/dev/null | awk '{sum+=$1} END{print sum+0}')
  warn "Found $CORE_COUNT core dump file(s) (~$((CORE_KB/1024)) MB total)"
  echo "$ALL_CORES" | head -10 | sed 's/^/    /'
  if command -v coredumpctl &>/dev/null; then
    coredumpctl list --no-pager 2>/dev/null | grep -v '^TIME' | tail -10 | sed 's/^/    /' || true
  fi
  if ask "remove core dumps" "~$((CORE_KB/1024)) MB"; then
    echo "$ALL_CORES" | xargs -r rm -f
    success "Core dumps removed"
  fi
else
  info "No core dumps found"
fi

# ── 9. Docker (if present) ───────────────────────────────────────────────────
header "Docker"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  # Overall disk usage with headers
  info "Disk usage summary:"
  docker system df 2>/dev/null
  echo ""

  # Per-image breakdown: mark each as USED (by a container) or UNUSED
  info "Images (USED = referenced by a container, even if stopped):"
  printf "  %-8s %-55s %-8s %s\n" "STATUS" "IMAGE" "SIZE" "CONTAINERS"
  # .Image is the correct docker ps format field (not .ImageID which doesn't exist)
  USED_IMAGES=$(docker ps -a --format '{{.Image}}' 2>/dev/null | sort -u || true)
  # Use process substitution so the loop runs in the main shell (inherits colour
  # variables, and a non-zero exit inside the loop won't trigger set -e on a pipeline)
  while IFS=$'\t' read -r id repo size created; do
    if echo "$USED_IMAGES" | grep -qxF "$repo"; then
      status="${GREEN}USED  ${RESET}"
      cnames=$(docker ps -a --filter "ancestor=$repo" --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')
    else
      status="${YELLOW}UNUSED${RESET}"
      cnames=""
    fi
    printf "  ${status} %-55s %-8s %s\n" "$repo" "$size" "$cnames"
  done < <(docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null || true)

  echo ""
  # Container log files — flag large ones
  info "Container log file sizes:"
  printf "  %-12s %-20s %-8s %s\n" "CONTAINER" "NAME" "SIZE" "LOG PATH"
  docker ps -a --format '{{.ID}}\t{{.Names}}' 2>/dev/null \
  | while IFS=$'\t' read cid cname; do
      logpath=$(docker inspect --format='{{.LogPath}}' "$cid" 2>/dev/null)
      if [[ -f "$logpath" ]]; then
        sz=$(du -sh "$logpath" 2>/dev/null | cut -f1)
        printf "  %-12s %-20s %-8s %s\n" "${cid:0:12}" "$cname" "$sz" "$logpath"
      fi
    done

  echo ""
  if ask "docker system prune --volumes -f (removes stopped containers, dangling images, unused volumes)" "see above"; then
    docker system prune --volumes -f
    success "Docker pruned"
  fi
else
  info "Docker not running, skipping"
fi

# ── 10. Large files report ───────────────────────────────────────────────────
header "Large files report (informational)"
info "Top 30 largest files on the filesystem (excluding /proc /sys /dev):"
find / -xdev \
  \( -path /proc -o -path /sys -o -path /dev \) -prune -o \
  -type f -size +50M -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn \
  | head -30 \
  | awk '{printf "  %6.0f MB  %s\n", $1/1048576, $2}'

info "Top 20 largest directories:"
du -x --max-depth=4 / 2>/dev/null \
  | sort -rn \
  | head -20 \
  | awk '{printf "  %6.0f MB  %s\n", $1/1024, $2}'

# ── 11. Large media files report ─────────────────────────────────────────────
header "Large media files (informational, >20 MB)"
MEDIA_EXTS="-iname '*.mp4' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.mov'"
MEDIA_EXTS="$MEDIA_EXTS -o -iname '*.mp3' -o -iname '*.flac' -o -iname '*.wav'"
MEDIA_EXTS="$MEDIA_EXTS -o -iname '*.iso' -o -iname '*.img' -o -iname '*.tar'"
MEDIA_EXTS="$MEDIA_EXTS -o -iname '*.tar.gz' -o -iname '*.tar.xz' -o -iname '*.zip'"
eval "find /home /root /tmp /var/tmp -xdev \( $MEDIA_EXTS \) -size +20M -printf '%s\t%p\n'" 2>/dev/null \
  | sort -rn \
  | head -20 \
  | awk '{printf "  %6.0f MB  %s\n", $1/1048576, $2}' \
  || info "No large media/archive files found in home dirs"

# ── Summary ───────────────────────────────────────────────────────────────────
header "Done"
echo -e "${BOLD}Disk usage after cleanup:${RESET}"
df -h /
$DRY_RUN && warn "Dry-run mode: no changes were made. Re-run without --dry-run to apply."
