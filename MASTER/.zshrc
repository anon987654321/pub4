# MASTER Zsh Frontend
# Pure modern Zsh - no bashisms, no subshells for file operations

# Load Zsh modules for native functionality
zmodload zsh/mapfile    # Read files directly into arrays
zmodload zsh/stat       # File stat operations
zmodload zsh/datetime   # Date/time functions

# MASTER environment
export MASTER_ROOT="${MASTER_ROOT:-/home/dev/pub/MASTER}"
export MASTER_LIB="$MASTER_ROOT/lib"
export MASTER_BIN="$MASTER_ROOT/bin"
export PATH="$MASTER_BIN:$PATH"

# Pure Zsh file operations (no cat, no subshells)
# Read entire file into variable
read_file() {
  [[ -f $1 ]] || return 1
  local content=${mapfile[$1]}
  print -r -- "$content"
}

# Read file into array (line by line)
read_lines() {
  [[ -f $1 ]] || return 1
  local -a lines
  lines=("${(@f)mapfile[$1]}")
  print -l -- "${lines[@]}"
}

# Write content to file
write_file() {
  local file=$1
  shift
  print -r -- "$@" >| "$file"
}

# Append to file
append_file() {
  local file=$1
  shift
  print -r -- "$@" >> "$file"
}

# Get file modification time
file_mtime() {
  [[ -f $1 ]] || return 1
  local -A stat_info
  zstat -A stat_info -H "$1"
  print -- "${stat_info[mtime]}"
}

# Get file size
file_size() {
  [[ -f $1 ]] || return 1
  local -A stat_info
  zstat -A stat_info -H "$1"
  print -- "${stat_info[size]}"
}

# Modern parameter expansion patterns
# Get directory: ${var:h}
# Get filename: ${var:t}
# Get extension: ${var:e}
# Remove extension: ${var:r}

# Glob qualifiers examples:
# *.rb(.)      - Regular files only
# *.rb(.om[1]) - Most recently modified file
# **/*.rb(.)   - Recursive regular files
# *.rb(.N)     - Null glob (no error if no match)

# Find most recent Ruby file
latest_rb() {
  local file
  file=(**/*.rb(.om[1]N))
  [[ -n $file ]] && print -- "$file"
}

# Find all Ruby files modified in last N minutes
recent_rb() {
  local mins=${1:-30}
  print -l -- **/*.rb(.mm-${mins}N)
}

# Count lines in files without cat
count_lines() {
  local total=0
  for file in "$@"; do
    [[ -f $file ]] || continue
    local -a lines=("${(@f)mapfile[$file]}")
    (( total += ${#lines} ))
  done
  print -- "$total"
}

# MASTER CLI integration
master() {
  ruby -I"$MASTER_LIB" "$MASTER_BIN/cli" "$@"
}

# Quick commands
alias m='master'
alias ma='master ask'
alias ms='master scan'
alias me='master evolve'

# Git aliases using Zsh parameter expansion
alias gs='git status --short'
alias gd='git --no-pager diff'
alias gl='git --no-pager log --oneline -10'

# Zsh-native directory stack operations
alias d='dirs -v'
alias 1='cd -1'
alias 2='cd -2'
alias 3='cd -3'

# Prompt
PROMPT="%F{cyan}master%f@%F{yellow}%m%f %F{green}%1~%f %# "

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Completion
autoload -Uz compinit
compinit -d ~/.zcompdump

# Key bindings
bindkey -e  # Emacs mode
bindkey '^R' history-incremental-search-backward

# Load local customizations if they exist
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
