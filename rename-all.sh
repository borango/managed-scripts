# renames all files in the current directory with a .mjs extension to a .js extension

from=".mjs"
to=".js"

from=$1
to=$2

for    file    in   *$from; do
git mv "$file" "${file%$from}$to" ||
    mv "$file" "${file%$from}$to"
done
