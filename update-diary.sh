#!/bin/bash

# Set diary directory (modify as needed)
DIARY_DIR="$HOME/diary"
mkdir -p "$DIARY_DIR"

# Get current date for diary filename
TODAY=$(date +%Y-%m-%d)
DIARY_FILE="$DIARY_DIR/$TODAY.md"

# Get current user's Git identity (name or email)
GIT_USER=$(git config user.name)
if [ -z "$GIT_USER" ]; then
    GIT_USER=$(git config user.email)
fi

# Initialize diary file if it doesn't exist
if [ ! -f "$DIARY_FILE" ]; then
    echo "# Diary Entry for $TODAY" > "$DIARY_FILE"
fi

# Find all Git repositories in home directory (modify path as needed)
find "$HOME" -type d -name ".git" -not -path "*/.git/*" | while read -r git_dir; do
    # Get the repo's working directory
    repo_dir=$(dirname "$git_dir")
    repo_name=$(basename "$repo_dir")

    echo -en "\ntesting $repo_name -"

    if [ -e ${repo_dir}/.dormant      ]; then echo -e "\t sleeps"; continue; fi #[indicates that we do not expect] any activity
    if [ -e ${repo_dir}/.diarydormant ]; then echo -e "\t skip." ; continue; fi #[...] contributions worth mentioning there

    # Navigate to repo and pull latest changes
    echo -e "\tharvesting ..."
    cd "$repo_dir" || continue
    git fetch # --all 

    # Get commits from all branches by the current user from the last 24 hours
    commits=$(git log --all --author="$GIT_USER" --since="24 hours ago" --pretty=format:"%ct %d %s")

    # Process each commit
    while IFS= read -r commit; do
        if [ -n "$commit" ]; then
            commit_time=$(echo "$commit" | cut -d' ' -f1)
            commit_message=$(echo "$commit" | cut -d' ' -f2-)
            # Determine if commit is from today or yesterday
            commit_date=$(date -d "@$commit_time" +%Y-%m-%d)
            if [ "$commit_date" = "$TODAY" ]; then
                prefix=""
            else
                prefix="yesterday: "
            fi
            topic="$prefix $repo_name: $commit_message"
            header="## $topic"

            # Check if header already exists to ensure idempotency
            if ! grep -Fx "$header"        "$DIARY_FILE" > /dev/null; then
                  echo -e "$header\n\n" >> "$DIARY_FILE"
		  echo  "+ $topic"
            fi
        fi
    done <<< "$commits"
done

# Add a section for non-Git notes if not already present
if ! grep -Fx "## [$TODAY] Non-Git Notes" "$DIARY_FILE" > /dev/null; then
    echo -e "\n## [$TODAY] Non-Git Notes\n" >> "$DIARY_FILE"
fi

echo "Diary updated: $DIARY_FILE"
