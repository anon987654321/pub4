#!/bin/bash

# Zsh Setup Script
echo "Setting up Zsh configuration..."

# Create backup directory
BACKUP_DIR="$HOME/.zsh_backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup existing configuration
if [ -f "$HOME/.zshrc" ]; then
    echo "Backing up existing .zshrc to $BACKUP_DIR"
    cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc"
fi

# Create zsh config directory
mkdir -p "$HOME/.zsh"

# Copy configuration files
echo "Installing configuration files..."
cp .zshrc "$HOME/.zshrc"
cp aliases.zsh "$HOME/.zsh/aliases.zsh"
cp functions.zsh "$HOME/.zsh/functions.zsh"

echo "Zsh configuration installed!"
echo "Run 'source ~/.zshrc' to apply changes"
