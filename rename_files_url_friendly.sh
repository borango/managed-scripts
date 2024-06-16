
# change space and open-parenthesis to underscore;
# remove comma, quote, and closing parenthesis
for f in *.pdf; do mv "$f" "$( sed s/[\ \(]/_/g <<< "$f" | sed s/[,\"\)]//g )"; done
