if [ -e $1/.git/config ]; then
  touch $1/.$(basename "${0%.*}")
else
  echo "error: $1 is not a Git repository"
  exit 1
fi
