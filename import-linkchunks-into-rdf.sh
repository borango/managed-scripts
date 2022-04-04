find -name '*' | while read j; do
 chunk_name=$(basename $j)
 echo -e "importing \033[1;33m" $chunk_name "\033[0m"
 curl http://localhost/symwork.atlassian.net/browse-link/$chunk_name?transfer=turtle
done
