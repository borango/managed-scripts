if [ -e $1/.git/config ]; then
  touch $1/.diarydormant
else
  echo "error: $1 is not a Git repository"
fi
