# Webchat Mode Setup for cli.rb

## Overview
cli.rb now supports FREE webchat mode using Ferrum (headless Chrome) to connect to free chat interfaces like chat.lmsys.org or HuggingChat.

## Requirements

### 1. Install Ferrum gem
```bash
gem install ferrum
```

### 2. Install Chrome/Chromium
**OpenBSD:**
```bash
doas pkg_add chromium
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt install chromium-browser
```

**Linux (Arch):**
```bash
sudo pacman -S chromium
```

### 3. Fix DNS (OpenBSD VM specific)
If you're on a VM with DNS issues:

```bash
# Check current DNS
cat /etc/resolv.conf

# If DNS isn't working, add public DNS
doas sh -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'
doas sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'

# Test
ping -c 2 chat.lmsys.org
```

### 4. Set Browser Path (if needed)
If browser isn't in standard location:
```bash
export BROWSER_PATH="/usr/local/bin/chrome"
```

## Usage

### Auto-detect mode (uses webchat if no API key)
```bash
cd ~/pub
./cli.rb
```

### Force webchat mode
```bash
./cli.rb --webchat lmsys      # Use LMSYS Chatbot Arena (default)
./cli.rb --webchat huggingchat # Use HuggingChat
```

### With API key (uses Anthropic API)
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
./cli.rb
```

## Supported Providers

### LMSYS Chatbot Arena (chat.lmsys.org)
- **Pros:** Free, multiple models, good quality
- **Cons:** Slower, no tool support
- **Best for:** General chat, testing

### HuggingChat (huggingface.co/chat)
- **Pros:** Free, open source models
- **Cons:** May require login, variable quality
- **Best for:** Experimentation

## Troubleshooting

### DNS Resolution Errors
```bash
# Check if DNS works
curl -I https://chat.lmsys.org

# If not, fix DNS in /etc/resolv.conf
```

### Browser Not Found
```bash
# Find your browser
which chrome chromium google-chrome

# Set path
export BROWSER_PATH="/path/to/browser"
```

### Timeout Issues
The webchat client waits up to 60 seconds for responses. If it times out:
- Check network connection
- Try a different provider
- Use API mode instead

## Mode Comparison

| Feature | API Mode | Webchat Mode |
|---------|----------|--------------|
| Cost | Paid ($) | FREE |
| Speed | Fast | Slower |
| Tools | Yes | No |
| Reliability | High | Medium |
| Setup | API key only | Browser + network |
| Best for | Production | Learning/testing |

## Current Status on Your VPS

✅ Ferrum gem installed
✅ Chrome browser installed at `/usr/local/bin/chrome`
❌ DNS resolution not working (needs fixing)

### To fix and test:
```bash
# Fix DNS
doas sh -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'

# Test
cd ~/pub
./cli.rb --webchat lmsys
```
