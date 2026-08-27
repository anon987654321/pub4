#!/usr/bin/env zsh
# fix_macos.sh
# Autonomous macOS setup — configs tracked in FUN/config/, aesthetic via MASTER_AESTHETIC.
# Default: openbsd wscons green. Optional: MASTER_AESTHETIC=phosphor SKETCHYBAR=1.
# Single execution required. Restart + Accessibility approvals afterward.

set -euo pipefail
trap 'print -P "%F{red}Setup interrupted.%f"; exit 1' INT

typeset SCRIPT_DIR=${0:A:h}
typeset CONFIG_DIR="${SCRIPT_DIR}/config"
typeset AESTHETIC=${MASTER_AESTHETIC:-wscons}
typeset PUB4_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

install_file() {
    typeset src=$1 dest=$2
    mkdir -p "$(dirname "${dest}")"
    cp -f "${src}" "${dest}"
}

install_exec() {
    install_file "$@"
    chmod +x "$2"
}

print -P "%F{blue}Starting autonomous macOS setup (aesthetic=${AESTHETIC})...%f"

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

brew tap FelixKratz/formulae
brew trust felixkratz/formulae 2>/dev/null || true
brew tap asmvik/formulae 2>/dev/null || true
brew trust asmvik/formulae 2>/dev/null || true
brew tap nikitabobko/tap 2>/dev/null || true
brew trust nikitabobko/tap 2>/dev/null || true

print -P "Installing packages..."

FORMULAS=(skhd starship borders bat zoxide fzf)
[[ ${SKETCHYBAR:-0} == 1 ]] && FORMULAS+=(sketchybar)
for pkg in "${FORMULAS[@]}"; do
    brew list "$pkg" &>/dev/null || brew install "$pkg"
done

CASKS=(ghostty nikitabobko/tap/aerospace jordanbaird-ice font-jetbrains-mono font-spleen)
for pkg in "${CASKS[@]}"; do
    brew list --cask "$pkg" &>/dev/null || brew install --cask "$pkg"
done

print -P "Verifying Homebrew..."
if brew doctor &>/dev/null; then
    print -P "%F{green}Homebrew verified.%f"
else
    print -P "%F{yellow}Homebrew warnings detected (usually harmless).%f"
fi

print -P "Installing tracked configs from ${CONFIG_DIR}..."

[[ -f "${CONFIG_DIR}/ghostty/${AESTHETIC}.config" ]] || {
    print -P "%F{red}Unknown MASTER_AESTHETIC=${AESTHETIC} (use wscons or phosphor)%f"
    exit 1
}

install_file "${CONFIG_DIR}/ghostty/${AESTHETIC}.config" ~/.config/ghostty/config
install_file "${CONFIG_DIR}/starship/${AESTHETIC}.toml" ~/.config/starship.toml
install_exec "${CONFIG_DIR}/borders/${AESTHETIC}.bordersrc" ~/.config/borders/bordersrc
install_file "${CONFIG_DIR}/skhd/skhdrc" ~/.config/skhd/skhdrc

if [[ ${SKETCHYBAR:-0} == 1 ]]; then
    install_exec "${CONFIG_DIR}/sketchybar/sketchybarrc" ~/.config/sketchybar/sketchybarrc
    install_file "${CONFIG_DIR}/aerospace/aerospace-sketchybar.toml" ~/.config/aerospace/aerospace.toml
else
    install_file "${CONFIG_DIR}/aerospace/aerospace.toml" ~/.config/aerospace/aerospace.toml
fi

# Zsh — replace pub4 block or append fresh block
print -P "Updating shell configuration..."
touch ~/.zshrc
if grep -q '# >>> pub4 fix_macos >>>' ~/.zshrc 2>/dev/null; then
    perl -0pi -e 's/# >>> pub4 fix_macos >>>.*?# <<< pub4 fix_macos <<<\n?//ms' ~/.zshrc
fi
cat "${CONFIG_DIR}/zshrc.macos" >> ~/.zshrc

# Start services
print -P "Starting services..."
pgrep -x skhd >/dev/null 2>&1 || skhd &

for app in AeroSpace Ghostty Ice; do
    if [[ -d "/Applications/${app}.app" ]]; then
        xattr -d com.apple.quarantine "/Applications/${app}.app" 2>/dev/null || true
    fi
done

open -a AeroSpace 2>/dev/null || true
open -a Ice 2>/dev/null || true
open -a Ghostty 2>/dev/null || true

# Verification
print -P "Verifying setup..."
typeset -i setup_warn=0
command -v starship >/dev/null || { print -P "%F{yellow}WARN: starship not on PATH%f"; setup_warn+=1 }
starship explain >/dev/null 2>&1 || { print -P "%F{yellow}WARN: starship config failed%f"; setup_warn+=1 }
[[ -f ~/.config/ghostty/config ]] || { print -P "%F{yellow}WARN: ghostty config missing%f"; setup_warn+=1 }
[[ -d /Applications/Ghostty.app ]] || { print -P "%F{yellow}WARN: Ghostty.app missing%f"; setup_warn+=1 }

if (( setup_warn == 0 )); then
    print -P "%F{green}Setup complete. Ghostty is your configured terminal.%f"
else
    print -P "%F{yellow}Setup finished with ${setup_warn} warning(s).%f"
fi
print -P "%F{yellow}Restart your Mac, then approve under System Settings → Privacy & Security → Accessibility:%f"
print -P "%F{yellow}  AeroSpace, skhd, borders (Input Monitoring for skhd).%f"
print -P "%F{yellow}Quit Terminal.app — use Ghostty (Ctrl+Shift+Enter) or MASTER_AESTHETIC=phosphor to switch palettes.%f"