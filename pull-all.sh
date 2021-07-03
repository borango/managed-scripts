find -type d -name ".git" -exec bash -c 'cd $(dirname {}); echo -n "pulling into $(basename $(pwd)) : "; git pull --ff-only' \;
