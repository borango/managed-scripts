#!/bin/bash

# Check if heif-convert is installed
if ! command -v heif-convert &> /dev/null
then
    echo "heif-convert could not be found. Please install it to use this script."
    exit 1
fi

# Loop through all HEIC files in the current directory
for file in *.heic; do
    # Get the base name of the file without the extension
    base_name="${file%.*}"
    # Construct the output file name with jpg extension
    output_file="${base_name}.jpg"
    
    # Check if the output file already exists
    if [[ -e "$output_file" ]]; then
        echo "Skipping conversion for $file as $output_file already exists."
        continue
    fi
    
    # Convert the HEIC file to JPG
    heif-convert "$file" "$output_file"
    # Print a message indicating the conversion
    echo "Converted $file to $output_file"
done

echo "Batch conversion completed."
