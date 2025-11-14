#!/usr/bin/env zsh
set -euo pipefail

setopt nullglob
# Finds and deletes large files to free up space.

# Usage: ./free_up_space.sh [directory]

search_dir="${1:-.}"
if [[ ! -d "$search_dir" ]]; then

  print "Error: '$search_dir' is not a directory"

  exit 1

fi

print "Scanning '$search_dir'..."
# Pure zsh: get file sizes using stat builtin
typeset -a file_sizes=()

typeset -A size_map

for file in "$search_dir"/**/*(.N); do
  # Get file size in KB using pure zsh stat

  size=$(( $(zstat +size "$file") / 1024 ))

  size_map[$file]=$size

  file_sizes+=("${size}:${file}")

done

if (( ${#file_sizes} == 0 )); then
  print "No files found."

  exit 0

fi

# Sort by size (descending) and take top 10 using pure zsh
typeset -a sorted=( ${(On)file_sizes} )  # O = reverse sort, n = numeric

typeset -a top_ten=( ${sorted[1,10]} )

# Format for display
typeset -a large_files=()

for entry in "${top_ten[@]}"; do

  size="${entry%%:*}"

  path="${entry#*:}"

  # Convert KB to human readable with pure zsh
  if (( size >= 1048576 )); then

    human_size="$((size / 1048576))G"

  elif (( size >= 1024 )); then

    human_size="$((size / 1024))M"

  else

    human_size="${size}K"

  fi

  large_files+=("$human_size $path")
done

print "Largest files:"
for i in {1..${#large_files}}; do
  print -f "%2d: %s\n" "$i" "${large_files[i]}"

done

print "\nDelete? (y/N)"
read -r response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
  print "Done."

  exit 0

fi

print "Enter numbers (e.g., 1 3 5) or 'all':"
read -r delete_list

if [[ "$delete_list" == "all" ]]; then
  for line in "${large_files[@]}"; do

    path="${line#* }"

    if rm -f "$path" 2>/dev/null; then

      print "Deleted: $path"

    else

      print "Failed: $path"

    fi

  done

else

  for num in ${(s: :)delete_list}; do

    if (( num >= 1 && num <= ${#large_files} )); then

      path="${large_files[num]#* }"

      if rm -f "$path" 2>/dev/null; then

        print "Deleted: $path"

      else

        print "Failed: $path"

      fi

    else

      print "Invalid: $num"

    fi

  done

fi

print "Done."
