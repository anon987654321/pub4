#!/usr/bin/env zsh
# Modernize all .sh files to pure zsh patterns per master.yml v17.0.0

set -euo pipefail
emulate -L zsh

typeset -a files
files=(${(f)"$(find . -name '*.sh' -type f ! -name 'modernize_zsh.sh')"})

for file in $files; do
  print "Processing: $file"

  # Replace local → typeset
  sed -i 's/\blocal /typeset /g' "$file"

  # Replace ${var,,} → ${var:l}  (bash lowercase to zsh)
  sed -i 's/\${\([^}]*\),,}/\${\1:l}/g' "$file"

  # Replace ${var^^} → ${var:u}  (bash uppercase to zsh)
  sed -i 's/\${\([^}]*\)\^\^}/\${\1:u}/g' "$file"

  # Replace ${var^} → ${(C)var}  (bash capitalize to zsh)
  sed -i 's/\${\([^}]*\)\^}/\${(C)\1}/g' "$file"

  print "  ✓ Modernized"
done

print "\nDone: ${#files} files processed"
