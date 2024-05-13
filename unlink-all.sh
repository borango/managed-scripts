# write bash script to unlink all softlinks in current directory

for file in *; do
    if [ -L "$file" ]; then
        unlink "$file"
    fi
done
