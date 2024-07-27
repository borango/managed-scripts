curl http://localhost:11434/api/tags | jq -r '.models | sort_by( .size ) | .[].model'
