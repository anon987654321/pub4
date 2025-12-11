#!/bin/sh
# Install script for Claude CLI

set -e

echo "============================================"
echo "Claude CLI Installation"
echo "============================================"
echo

# Check Ruby version
echo "Checking Ruby installation..."
if ! command -v ruby >/dev/null 2>&1; then
    echo "Error: Ruby is not installed"
    echo "Please install Ruby 2.7+ and try again"
    exit 1
fi

RUBY_VERSION=$(ruby -e 'print RUBY_VERSION')
echo "Found Ruby version: $RUBY_VERSION"

# Check if version is >= 2.7
MAJOR=$(echo $RUBY_VERSION | cut -d. -f1)
MINOR=$(echo $RUBY_VERSION | cut -d. -f2)
if [ "$MAJOR" -lt 2 ] || ([ "$MAJOR" -eq 2 ] && [ "$MINOR" -lt 7 ]); then
    echo "Warning: Ruby 2.7+ is recommended (found $RUBY_VERSION)"
fi

echo

# Check for SQLite3 gem
echo "Checking for SQLite3 gem..."
if ruby -e 'require "sqlite3"' 2>/dev/null; then
    echo "✓ SQLite3 gem is installed"
else
    echo "SQLite3 gem not found"
    echo
    echo "The CLI can work without SQLite3, but sessions won't be persisted."
    echo "Would you like to install the sqlite3 gem? (y/n)"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        echo "Installing sqlite3 gem..."
        gem install sqlite3 --no-document
        echo "✓ SQLite3 gem installed"
    else
        echo "Skipping SQLite3 installation"
    fi
fi

echo

# Make cli.rb executable
echo "Making cli.rb executable..."
chmod +x cli.rb
echo "✓ cli.rb is now executable"

echo

# Create directories
echo "Creating configuration directories..."
mkdir -p "$HOME/.claude"
echo "✓ Created $HOME/.claude/"

echo

# Offer to create symlink
echo "Would you like to create a symlink to run 'claude' from anywhere? (y/n)"
read -r answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    # Determine installation location
    if [ -d "$HOME/bin" ]; then
        BIN_DIR="$HOME/bin"
    elif [ -d "$HOME/.local/bin" ]; then
        BIN_DIR="$HOME/.local/bin"
    else
        echo "Creating $HOME/bin..."
        mkdir -p "$HOME/bin"
        BIN_DIR="$HOME/bin"
    fi
    
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    ln -sf "$SCRIPT_DIR/cli.rb" "$BIN_DIR/claude"
    echo "✓ Created symlink: $BIN_DIR/claude -> $SCRIPT_DIR/cli.rb"
    echo
    echo "Make sure $BIN_DIR is in your PATH:"
    echo "  export PATH=\"\$HOME/bin:\$PATH\"  # Add to your ~/.bashrc or ~/.zshrc"
else
    echo "Skipping symlink creation"
    echo "You can run the CLI with: ./cli.rb"
fi

echo
echo "============================================"
echo "Installation Complete!"
echo "============================================"
echo
echo "Next steps:"
echo "1. Set your Claude API key:"
echo "   ./cli.rb"
echo "   /config set api_key YOUR_API_KEY"
echo "   /config save"
echo
echo "2. Or set it directly in the config file:"
echo "   Edit ~/.claude/config.yml"
echo
echo "3. Start chatting:"
echo "   ./cli.rb"
echo
echo "For help, type /help in the CLI"
echo
