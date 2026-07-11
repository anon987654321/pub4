#!/usr/bin/env zsh
# fix_macos.sh
# Fully autonomous macOS setup with flat SGI IRIX-style UI and AeroSpace tiling.
# Single execution required. Restart + Accessibility approvals afterward.

set -euo pipefail
trap 'print -P "%F{red}Setup interrupted.%f"; exit 1' INT

print -P "%F{blue}Starting autonomous macOS setup...%f"

# macOS system defaults
print -P "Applying clean macOS defaults..."

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock tilesize -int 36
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.finder CreateDesktop -bool false
defaults write com.apple.finder ShowStatusBar -bool true
defaults write NSGlobalDomain _HIHideMenuBar -bool true
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
defaults write -g NSWindowShouldDragOnGesture -bool true

killall Dock Finder SystemUIServer 2>/dev/null || true

# Homebrew
if ! command -v brew &>/dev/null; then
    print -P "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if command -v brew &>/dev/null; then
    eval "$(brew shellenv)"
fi

export HOMEBREW_NO_AUTO_UPDATE=1

# Taps (Homebrew 5+ requires explicit trust for third-party formulae)
brew tap FelixKratz/formulae
brew trust felixkratz/formulae 2>/dev/null || true
brew tap asmvik/formulae 2>/dev/null || true
brew trust asmvik/formulae 2>/dev/null || true
brew tap nikitabobko/tap 2>/dev/null || true
brew trust nikitabobko/tap 2>/dev/null || true

# Install packages
print -P "Installing packages..."

FORMULAS=(skhd starship borders sketchybar eza bat zoxide fzf)
for pkg in "${FORMULAS[@]}"; do
    brew list "$pkg" &>/dev/null || brew install "$pkg"
done

CASKS=(ghostty nikitabobko/tap/aerospace jordanbaird-ice font-jetbrains-mono-nerd-font)
for pkg in "${CASKS[@]}"; do
    brew list --cask "$pkg" &>/dev/null || brew install --cask "$pkg"
done

# Homebrew dependency verification
print -P "Verifying Homebrew..."

if brew doctor &>/dev/null; then
    print -P "%F{green}Homebrew verified.%f"
else
    print -P "%F{yellow}Homebrew warnings detected (usually harmless).%f"
fi

# Create configurations
print -P "Creating configurations..."

# AeroSpace
mkdir -p ~/.config/aerospace
cat > ~/.config/aerospace/aerospace.toml << 'EOF'
config-version = 2
start-at-login = true
auto-reload-config = true

default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

gaps.inner.horizontal = 8
gaps.inner.vertical = 8
gaps.outer.left = 8
gaps.outer.bottom = 8
gaps.outer.top = 8
gaps.outer.right = 8

after-startup-command = [
    'exec-and-forget borders active_color=0xff00d4ff inactive_color=0xff1b263b width=5.0',
    'exec-and-forget sketchybar',
]

[mode.main.binding]
    ctrl-shift-return = 'exec-and-forget open -a Ghostty'
    ctrl-shift-t = 'exec-and-forget open -a Ghostty'
    ctrl-shift-space = '''exec-and-forget osascript -e 'tell application "System Events" to keystroke space using {command down}' '''

    alt-slash = 'layout tiles horizontal vertical'
    alt-comma = 'layout accordion horizontal vertical'

    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'

    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'

    alt-minus = 'resize smart -50'
    alt-equal = 'resize smart +50'

    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'

    alt-tab = 'workspace-back-and-forth'
    alt-shift-semicolon = 'mode service'

[mode.service.binding]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main']
    f = ['layout floating tiling', 'mode main']
    backspace = ['close-all-windows-but-current', 'mode main']
EOF

# skhd (works before AeroSpace Accessibility approval)
mkdir -p ~/.config/skhd
cat > ~/.config/skhd/skhdrc << 'EOF'
ctrl + shift - return : open -a Ghostty
ctrl + shift - space : osascript -e 'tell application "System Events" to keystroke space using {command down}'
ctrl + shift - l : /System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend
EOF

# Ghostty
mkdir -p ~/.config/ghostty
cat > ~/.config/ghostty/config << 'EOF'
font-family = "JetBrainsMono Nerd Font"
font-size = 16

background = #0d1b2a
foreground = #00d4ff
background-opacity = 0.95
background-blur = 0

macos-titlebar-style = hidden
window-padding-x = 16
window-padding-y = 16
tab-bar-location = hidden
scrollbar-location = never

cursor-style = block
cursor-style-blink = false
mouse-hide-while-typing = true
EOF

# JankyBorders (used when borders is started via brew services)
mkdir -p ~/.config/borders
cat > ~/.config/borders/bordersrc << 'EOF'
#!/bin/bash

options=(
    active_color=0xff00d4ff
    inactive_color=0xff1b263b
    width=5.0
)

borders "${options[@]}"
EOF
chmod +x ~/.config/borders/bordersrc

# Sketchybar
mkdir -p ~/.config/sketchybar
cat > ~/.config/sketchybar/sketchybarrc << 'EOF'
#!/usr/bin/env zsh

sketchybar --bar height=32 \
                 color=0xff0d1b2a \
                 border_color=0xff00d4ff \
                 border_width=2

sketchybar --add item clock right \
           --set clock update_freq=30 \
                     icon.drawing=off \
                     script='date "+%H:%M"' \
                     label.color=0xff00d4ff \
                     background.color=0xff1b263b
EOF
chmod +x ~/.config/sketchybar/sketchybarrc

# Starship
mkdir -p ~/.config
cat > ~/.config/starship.toml << 'EOF'
add_newline = false

[character]
success_symbol = "[➜](bold cyan)"
EOF

# Zsh configuration
print -P "Updating shell configuration..."

touch ~/.zshrc
grep -q "starship" ~/.zshrc 2>/dev/null || printf '\neval "$(starship init zsh)"\n' >> ~/.zshrc
grep -q "eza" ~/.zshrc 2>/dev/null || printf '\nalias ls="eza --icons"\nalias ll="eza -l --icons"\n' >> ~/.zshrc
grep -q "zoxide" ~/.zshrc 2>/dev/null || printf '\neval "$(zoxide init zsh)"\n' >> ~/.zshrc
grep -q "fzf" ~/.zshrc 2>/dev/null || printf '\nsource <(fzf --zsh)\n' >> ~/.zshrc

# Start services
print -P "Starting services..."

brew services start skhd 2>/dev/null || true

# Remove quarantine flags on freshly installed GUI apps
for app in AeroSpace Ghostty Ice; do
    if [[ -d "/Applications/${app}.app" ]]; then
        xattr -d com.apple.quarantine "/Applications/${app}.app" 2>/dev/null || true
    fi
done

open -a AeroSpace 2>/dev/null || true
open -a Ice 2>/dev/null || true

# Final message
print -P "%F{green}Setup complete.%f"
print -P "%F{yellow}Restart your Mac, then approve these apps under System Settings → Privacy & Security → Accessibility:%f"
print -P "%F{yellow}  AeroSpace, skhd, borders (and Input Monitoring for skhd).%f"