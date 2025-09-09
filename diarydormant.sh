if [ -e $1/.git/config ]; then
  touch $1/.dormant
else
  echo "error: $1 is not a Git repository"
fi
