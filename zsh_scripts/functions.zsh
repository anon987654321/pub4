#!/usr/bin/env zsh

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract various archive formats
extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"    ;;
            *.tar.gz)    tar xzf "$1"    ;;
            *.bz2)       bunzip2 "$1"    ;;
            *.rar)       unrar x "$1"    ;;
            *.gz)        gunzip "$1"     ;;
            *.tar)       tar xf "$1"     ;;
            *.tbz2)      tar xjf "$1"    ;;
            *.tgz)       tar xzf "$1"    ;;
            *.zip)       unzip "$1"      ;;
            *.Z)         uncompress "$1" ;;
            *.7z)        7z x "$1"       ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Find file by name
ff() {
    find . -type f -name "*$1*"
}

# Find directory by name
fd() {
    find . -type d -name "*$1*"
}

# Quick backup of a file
backup() {
    cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
}

# Display system information
sysinfo() {
    echo "Hostname: $(hostname)"
    if command -v uptime >/dev/null 2>&1; then
        echo "Uptime: $(uptime | sed 's/.*up //' | sed 's/,.*//')"
    fi
    if command -v uname >/dev/null 2>&1; then
        echo "OS: $(uname -s) $(uname -r)"
    fi
    if command -v free >/dev/null 2>&1; then
        echo "Memory: $(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')"
    fi
    echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
}
