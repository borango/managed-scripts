#

scriptfile=lastcommand.sh

history | grep -F "$1" | tail -n 2 | head -n 1 | sed 's/^[ ]*[0-9]\+[ ]*//' | tee > $scriptfile
chmod +x $scriptfile
