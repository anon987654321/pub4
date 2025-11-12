#!/usr/bin/env zsh

# Navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Listing aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# System aliases
alias update='sudo apt update && sudo apt upgrade'
alias ports='netstat -tulanp'
alias meminfo='free -m -l -t'
alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Development aliases
alias py='python3'
alias rb='ruby'
alias serve='python3 -m http.server'
