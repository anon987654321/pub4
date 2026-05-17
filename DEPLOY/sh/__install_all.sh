#!/usr/bin/env zsh
# Install utility scripts from sh/ to ~/bin and add ~/bin to PATH.

set -euo pipefail

typeset target=$HOME/bin
[[ -d $target ]] || mkdir -p "$target"

typeset script name
for script in ${0:a:h}/*.sh; do
  name=${script:t:r}
  [[ $name == __install_all ]] && continue
  cp "$script" "$target/$name"
  chmod +x "$target/$name"
  print -r -- "installed: $name"
done

typeset path_line='export PATH="$HOME/bin:$PATH"'
typeset rc=${ZDOTDIR:-$HOME}/.zshrc
[[ -f $rc && $(<$rc) == *$path_line* ]] || print -r -- "\n$path_line" >> "$rc"
print -r -- "done"
