#!/usr/bin/env zsh
# Modernize all .sh files to pure zsh patterns per master.yml v206

emulate -L zsh
setopt extended_glob

typeset -a files
files=(${(f)"$(find . -name '*.sh' -type f ! -name 'modernize_zsh.sh')"})

for file in $files; do
  print "Processing: $file"
  
  # Read entire file
  typeset content=$(<$file)
  
  # Replace local → typeset
  content=${content//local /typeset }
  
  # Replace ${var,,} → ${var:l}  (lowercase)
  content=${content//\$\{([^}]##),,\}/\$\{${1}:l\}}
  
  # Replace ${var^^} → ${var:u}  (uppercase)
  content=${content//\$\{([^}]##)\^\^\}/\$\{${1}:u\}}
  
  # Replace ${var^} → ${(C)var}  (capitalize)
  content=${content//\$\{([^}]##)\^\}/\$\{(C)${1}\}}
  
  # Write back
  print -r -- "$content" > $file
  
  print "  ✓ Modernized"
done

print "\nDone: ${#files} files processed"
