unalias ls

# find -name   '*-*' | \
# ls -A1tr  -I '*-*' | \

# list chunks with are not of *-* pattern and also skip trash/ folder
  ls -A1trp -I '*-*' | grep -v /$ | \
while read j; do
 chunk_name=$(basename $j)
 #echo -e "importing \033[1;33m" $chunk_name "\033[0m"
 echo -n .
 curl http://localhost/symwork.atlassian.net/browse/$chunk_name?transfer=turtle&reduce=all
done
