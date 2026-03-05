#!/usr/bin/env zsh
# Sets up utility scripts in ~/bin and adds them to PATH.
# Usage: ./__install_all.sh

set -euo pipefail

echo "Installing scripts..."

log_file="$HOME/script_errors.log"
[[ -f "$log_file" ]] && rm "$log_file"

cat << 'EOF' > backup.sh
# Archives folders to dated .tgz files, skips unchanged ones.
# Usage: ./backup.sh [directory]


log_error() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$HOME/script_errors.log"; }

dir="${1:-.}"
checksum_file="$dir/.backup_checksums"
date_format=$(date +"%Y%m%d")
cd "$dir" || exit 1

# Load prior checksums to check for changes.
typeset -A old_checksums
if [[ -f "$checksum_file" ]]; then
  while read -r folder checksum; do
    old_checksums["$folder"]="$checksum"
  done < "$checksum_file"
fi

typeset -A new_checksums

for subdir in */(N); do
  folder="${subdir%/}"
  
  # Creates a unique hash from all files in folder.
  checksum=$(find "$folder" -type f -exec md5 -q {} + | sort | md5 -q)
  new_checksums["$folder"]="$checksum"

  backup_file="${folder}_${date_format}.tgz"
  if [[ -z "${old_checksums[$folder]}" || "${old_checksums[$folder]}" != "$checksum" ]]; then
    echo "Backing up: $folder -> $backup_file"
    tar cvzf "$backup_file" "$folder" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
      log_error "tar failed for $backup_file"
      echo "Failed: $backup_file"
    else
      echo "Created: $backup_file"
    fi
  else
    echo "Skipped (no changes): $folder"
  fi
done

# Updates checksum file for next run.
for folder in ${(k)new_checksums}; do
  echo "$folder ${new_checksums[$folder]}"
done > "$checksum_file"
EOF
chmod +x backup.sh

# ---

cat << 'EOF' > clean.sh
# Removes carriage returns, trailing whitespaces, and extra blank lines from text files.
# Usage: ./clean.sh [target_folder]


dir="${1:-.}"

if [[ ! -d "$dir" ]]; then
  echo "Error: '$dir' is not a directory"
  exit 1
fi

for file in "$dir"/**/*(.N); do
  if file -b "$file" | grep -q "text"; then
  
    tmp=$(mktemp)
    if [[ $? -ne 0 ]]; then
      echo "Error: mktemp failed"
      exit 1
    fi
    
    # Removes CRLF, trims trailing whitespaces, reduces blank lines.
    tr -d '\r' < "$file" | awk '{sub(/[ \t]+$/, "");} NF{print; if(p)print ""} {p=NF}' > "$tmp" 2>/dev/null
    if [[ $? -eq 0 ]]; then
      mv "$tmp" "$file"
      echo "Cleaned: $file"
    else
      rm "$tmp"
      echo "Failed: $file"
    fi
  fi
done
EOF
chmod +x clean.sh

# ---

cat << 'EOF' > hack.sh
# Finds text files matching a pattern and opens them in Vim.
# Usage: ./hack.sh [pattern]


pattern="$1"
if [[ -n "$pattern" ]]; then
  pattern=$(echo "$pattern" | sed 's/[.[\*^$]/\\&/g')
fi

typeset -a files_to_open

for file in **/*(.N); do
  is_text=$(file -b "$file" | grep -q "text"; echo $?)
  if [[ $is_text -eq 0 ]]; then
  
    if [[ -z "$pattern" ]]; then
      files_to_open+=("$file")
    elif grep -q "$pattern" "$file" 2>/dev/null; then
      files_to_open+=("$file")
    fi
  fi
done

if (( ${#files_to_open} > 0 )); then
  echo "Files found:"
  printf "  %s\n" "${files_to_open[@]}"
  
  echo "Open in Vim? (Y/n)"
  read -r response
  if [[ "${response:-Y}" =~ ^[Yy]$ ]]; then
    vim "${files_to_open[@]}"
  else
    echo "Cancelled."
  fi
else
  echo "No matching files."
fi
EOF
chmod +x hack.sh

# ---

cat << 'EOF' > lint.sh
# Checks and fixes Ruby code files for errors.
# Usage: ./lint.sh


check_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: $1 not found. Install it."
    exit 1
  fi
}

lint_ruby() {
  local file="$1"
  echo "Linting: $file"
  
  if ! reek "$file" >/dev/null 2>&1; then
    echo "Reek flagged: $file"
  fi
  if ! rubocop --autocorrect "$file" >/dev/null 2>&1; then
    echo "Rubocop failed: $file"
  fi
  
  echo "Done: $file"
}

check_tool "rubocop"
check_tool "reek"

find . -type f \( -name "*.rb" -o -name "*.erb" \) \
  ! -path "*/.gem/*" ! -path "*/vendor/*" | while read -r file; do
    lint_ruby "$file"
  done
EOF
chmod +x lint.sh

# ---

cat << 'EOF' > perms.sh
# Changes file ownership and permissions.
# Usage: ./perms.sh <owner> <group> <file_perms> <folder_perms>


if (( $# < 4 )); then
  echo "Usage: $0 <owner> <group> <file_perms> <folder_perms>"
  exit 1
fi

owner_group="$1:$2"
file_perms="$3"
folder_perms="$4"

if [[ ! "$file_perms" =~ ^[0-7]{3}$ ]]; then
  echo "Error: File perms must be 3 digits (e.g., 644)"
  exit 1
fi
if [[ ! "$folder_perms" =~ ^[0-7]{3}$ ]]; then
  echo "Error: Folder perms must be 3 digits (e.g., 755)"
  exit 1
fi

echo "Owner:group = $owner_group"
echo "File perms  = $file_perms"
echo "Folder perms = $folder_perms"

echo "Apply? (y/N)"
read -r confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  chown -R "$owner_group" ./**/* 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then
    echo "Some chown failed; see $HOME/script_errors.log"
  fi
  
  chmod -R "$file_perms" ./**/*(.) 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then
    echo "Some file perms failed"
  fi
  
  chmod -R "$folder_perms" ./**/*(/) 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then
    echo "Some folder perms failed"
  fi
  
  echo "Done."
else
  echo "Cancelled."
fi
EOF
chmod +x perms.sh

# ---

cat << 'EOF' > replace.sh
# Swaps out words in files or renames them.
# Usage: ./replace.sh [-b] <old> <new> [folder]


backup=false
if [[ "$1" == "-b" ]]; then
  backup=true
  shift
fi

is_filename=false
if [[ "$1" == "-f" ]]; then
  is_filename=true
  shift
fi

old_str="$1"
new_str="$2"
folder="${3:-.}"

if [[ -z "$old_str" || -z "$new_str" ]]; then
  echo "Error: Must provide old and new strings"
  exit 1
fi
if [[ ! -d "$folder" ]]; then
  echo "Error: '$folder' is not a directory"
  exit 1
fi

echo "Processing: $folder"
for file in "$folder"/**/*(.N); do
  if "$is_filename"; then
    new_file="${file//$old_str/$new_str}"
    if [[ "$file" != "$new_file" && ! -e "$new_file" ]]; then
      mv "$file" "$new_file" 2>/dev/null
      if [[ $? -eq 0 ]]; then
        echo "Renamed: $file -> $new_file"
      else
        echo "Failed: $file"
      fi
    fi
  else
    is_text=$(file -b "$file" | grep -q "text"; echo $?)
    if [[ $is_text -eq 0 ]]; then
      if grep -q "$old_str" "$file" 2>/dev/null; then
        if "$backup"; then
          cp "$file" "$file.bak" 2>/dev/null || echo "Backup failed: $file"
        fi
        
        sed "s|$old_str|$new_str|g" "$file" > "$file.tmp" 2>/dev/null
        if [[ $? -eq 0 ]]; then
          mv "$file.tmp" "$file"
          echo "Updated: $file"
        else
          echo "Failed: $file"
          rm -f "$file.tmp"
        fi
      fi
    fi
  fi
done
EOF
chmod +x replace.sh

# ---

cat << 'EOF' > showp.sh
# Creates a Markdown list of text files and their contents.
# Usage: ./showp.sh


root=$(basename "$PWD")
date=$(date +"%Y-%m-%d_%H%M%S")
output="$HOME/OUTPUT_${root}_${date}.md"

{
  for file in **/*(-.N); do
    if [[ "$file" == "$output" ]]; then
      continue
    fi
    
    if file -b "$file" | grep -q "text"; then
      echo "## \`${file#./}\`"
      echo '```'
      cat "$file" 2>/dev/null || echo "Read failed: $file"
      echo '```'
      echo
    fi
  done
} > "$output" 2>>"$HOME/script_errors.log"
if [[ $? -ne 0 ]]; then
  echo "Failed to write $output; see $HOME/script_errors.log"
  exit 1
fi

echo "Saved: $output"
EOF
chmod +x showp.sh

# ---

cat << 'EOF' > svgomg.sh
# Shrinks SVG files to save space.
# Usage: ./svgomg.sh [folder]


if ! command -v svgo >/dev/null 2>&1; then
  echo "Error: svgo not found. Install via npm."
  exit 1
fi

dir="${1:-.}"

if [[ ! -d "$dir" ]]; then
  echo "Error: '$dir' is not a directory"
  exit 1
fi

for svg in "$dir"/**/*.svg(.N); do
  svgo --pretty "$svg" 2>>"$HOME/script_errors.log"
  if [[ $? -eq 0 ]]; then
    echo "Processed: $svg"
  else
    echo "Failed: $svg; see $HOME/script_errors.log"
  fi
done
EOF
chmod +x svgomg.sh

# ---

cat << 'EOF' > tree.sh
# Displays a tree of directories and files.
# Usage: ./tree.sh [folder] [-a]


include_hidden=false
folder="."
for arg in "$@"; do
  if [[ "$arg" == "-a" ]]; then
    include_hidden=true
  else
    folder="$arg"
  fi
done

if [[ ! -d "$folder" ]]; then
  echo "Error: '$folder' is not a directory"
  exit 1
fi

print_tree() {
  local dir="$1" indent="${2:-}"
  for entry in "$dir"/*(N); do
    if [[ ! -e "$entry" ]]; then
      continue
    fi
    
    if [[ -d "$entry" ]]; then
      echo "${indent}+-- ${entry:t}/"
      print_tree "$entry" "${indent}|   "
    else
      echo "${indent}+-- ${entry:t}"
    fi
  done
}

print_tree "$folder"
EOF
chmod +x tree.sh

# ---

cat << 'EOF' > free_up_space.sh
# Finds and deletes large files to free up space.
# Usage: ./free_up_space.sh [directory]


search_dir="${1:-.}"

if [[ ! -d "$search_dir" ]]; then
  echo "Error: '$search_dir' is not a directory"
  exit 1
fi

echo "Scanning '$search_dir'..."
typeset -a large_files
# Lists top 10 largest files by size.
find "$search_dir" -type f -exec du -k {} + 2>/dev/null | sort -nr | head -n 10 | while read -r size path; do
  human_size=$(echo "$size" | awk '{printf "%.1fK", $1}')
  large_files+=("$human_size $path")
done

if (( ${#large_files} == 0 )); then
  echo "No files found."
  exit 0
fi

echo "Largest files:"
for i in {1..${#large_files}}; do
  printf "%2d: %s\n" "$i" "${large_files[i]}"
done

echo "\nDelete? (y/N)"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
  echo "Done."
  exit 0
fi

echo "Enter numbers (e.g., 1 3 5) or 'all':"
read -r delete_list

if [[ "$delete_list" == "all" ]]; then
  for line in "${large_files[@]}"; do
    path="${line#* }"
    if rm -f "$path" 2>/dev/null; then
      echo "Deleted: $path"
    else
      echo "Failed: $path"
    fi
  done
else
  for num in ${(s: :)delete_list}; do
    if (( num >= 1 && num <= ${#large_files} )); then
      path="${large_files[num]#* }"
      if rm -f "$path" 2>/dev/null; then
        echo "Deleted: $path"
      else
        echo "Failed: $path"
      fi
    else
      echo "Invalid: $num"
    fi
  done
fi

echo "Done."
EOF
chmod +x free_up_space.sh

# ---

# Deployment: Copy all tools to a place your computer can find them easily
target_dir="$HOME/bin"
if [[ ! -d "$target_dir" ]]; then
  echo "Creating $target_dir..."
  mkdir -p "$target_dir" 2>>"$log_file"
  if [[ $? -ne 0 ]]; then
    echo "Failed to create $target_dir; see $log_file"
    exit 1
  fi
fi

echo "Deploying to $target_dir..."
for script in *.sh; do
  if [[ "$script" == "install.sh" ]]; then
    continue
  fi
  dest="$target_dir/${script:r}"
  cp "$script" "$dest" 2>>"$log_file"
  chmod +x "$dest" 2>>"$log_file"
  if [[ $? -eq 0 ]]; then
    echo "Deployed: $dest"
  else
    echo "Failed: $script -> $dest"
  fi
done

shell_config=""
if [[ "$SHELL" == */zsh ]]; then
  shell_config="$HOME/.zshrc"
elif [[ "$SHELL" == */ksh ]]; then
  shell_config="$HOME/.kshrc"
else
  shell_config="$HOME/.profile"
fi

# Adds ~/bin to PATH for easy script access.
path_line="export PATH=\"\$HOME/bin:\$PATH\""
if ! grep -q "$path_line" "$shell_config" 2>/dev/null; then
  echo "\n# Added by install.sh" >> "$shell_config"
  echo "$path_line" >> "$shell_config"
  echo "Added $target_dir to PATH in $shell_config."
  echo "Run 'source $shell_config' to update your shell."
else
  echo "$target_dir already in PATH in $shell_config."
fi

echo "Deployment complete. Check $log_file for errors."

# All scripts installed.
echo "All scripts installed."

