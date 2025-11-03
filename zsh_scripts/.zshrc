# Zsh Configuration Example

# History settings
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# Enable colors
autoload -U colors && colors

# Custom prompt
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# Enable command completion
autoload -Uz compinit
compinit

# Load aliases and functions
[[ -f ~/.zsh/aliases.zsh ]] && source ~/.zsh/aliases.zsh
[[ -f ~/.zsh/functions.zsh ]] && source ~/.zsh/functions.zsh

# Key bindings
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Environment variables
export EDITOR=vim
export VISUAL=vim
export PATH="$HOME/bin:$PATH"

# Enable syntax highlighting (if installed)
# source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
