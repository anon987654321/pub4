# Claude CLI - Quick Start Guide

## Installation (1 minute)

```bash
# Clone or download the repository
cd pub4

# Run the install script
./install_cli.sh

# Or manually:
chmod +x cli.rb
gem install sqlite3 --no-document  # optional
```

## Configuration (30 seconds)

### Option 1: Interactive setup
```bash
./cli.rb
# You'll see: "API key not set. Use: claude config set api_key YOUR_KEY"

# In the CLI:
/config set api_key sk-ant-YOUR_KEY_HERE
/config save
/quit
```

### Option 2: Edit config file
```bash
# Copy example config
cp config.yml.example ~/.claude/config.yml

# Edit with your API key
nano ~/.claude/config.yml  # or vim, emacs, etc.
```

## Usage Examples

### Basic Chat
```bash
./cli.rb

You: What is the capital of France?
Claude: The capital of France is Paris...

You: Tell me more about it
Claude: Paris is known for...
```

### Code Help
```bash
You: How do I read a file in Ruby?

Claude: Here's how to read a file in Ruby:

```ruby
# Read entire file
content = File.read('file.txt')

# Read line by line
File.foreach('file.txt') do |line|
  puts line
end
```
```

### Configuration Commands
```bash
# View current settings
/config list

# Change model
/model claude-3-5-haiku-20241022

# Adjust creativity (temperature)
/temp 0.7

# Set max response length
/tokens 8192

# Toggle streaming
/stream

# Save changes
/config save
```

### Session Management
```bash
# View current session info
/session info

# List recent sessions
/session list

# Tag current session
/session tag debugging
/session tag python

# Search sessions
/session search "OpenBSD"

# Load previous session
/session load 5
```

### Master.yml Validation
```bash
# Validate master.yml structure
/master validate

# Output shows:
# ✓ All checks passed
# Checksum: a1b2c3d4...
```

### Clear Conversation
```bash
# Start fresh without restarting CLI
/clear
```

### Help
```bash
# Show all commands
/help

# Exit
/quit
```

## Common Workflows

### Quick Question
```bash
./cli.rb
You: Quick question about Ruby blocks
Claude: [answer]
/quit
```

### Long Conversation with History
```bash
./cli.rb
You: I'm working on a Rails app with authentication issues
Claude: I can help with that. What's the specific problem?
You: [explain issue]
Claude: [provides solution]
You: Thanks! Can you explain how [detail] works?
Claude: [detailed explanation]

# Later that day, resume:
/session list
# Shows: 3: 2025-12-11T14:30:00Z
/session load 3
# Your conversation history is restored
You: Following up on that authentication issue...
```

### Debugging Session
```bash
./cli.rb
/session tag debugging
/session tag production-issue

You: I'm seeing this error: [error message]
Claude: [debugging help]
You: [more details]
Claude: [solution]

/session info
# Shows token usage, cost, and metadata
```

### Research & Development
```bash
./cli.rb
/session tag research
/session tag algorithm-design

You: I need to implement a graph traversal algorithm
Claude: [explains options]
You: Let's go with BFS, show me an implementation
Claude: [provides code]
You: How would I optimize this for large graphs?
Claude: [optimization strategies]
```

## Tips & Tricks

### 1. Streaming vs Non-Streaming
- **Streaming ON** (default): See responses in real-time, like typing
- **Streaming OFF**: Full response appears at once
- Toggle anytime: `/stream`

### 2. Temperature Settings
- `0.0-0.3`: Focused, deterministic (good for code, facts)
- `0.7`: Balanced (default is 1.0)
- `0.8-1.0`: Creative, varied (good for brainstorming)

### 3. Model Selection
- **Haiku** (`/model claude-3-5-haiku-20241022`): Fast & cheap, simple tasks
- **Sonnet** (default): Best balance, most use cases
- **Opus** (`/model claude-3-opus-20240229`): Most capable, complex reasoning

### 4. Session Organization
- Tag sessions immediately: `/session tag project-name`
- Use descriptive tags: `/session tag bug-fix`, `/session tag planning`
- Search works on both tags and content: `/session search "authentication"`

### 5. Debug Mode
When things go wrong:
```bash
/config set debug true
# Now you'll see:
# [DEBUG] Rate limited (429), retrying in 2.0s...
# [DEBUG] Connection test failed: timeout
```

### 6. Cost Tracking
```bash
/session info
# Shows:
#   Total tokens: 12,450
#   Total cost: $0.1121
#   Avg response time: 2.34s
```

### 7. Configuration Presets
Create multiple config files for different use cases:
```bash
cp ~/.claude/config.yml ~/.claude/config-fast.yml  # Haiku model
cp ~/.claude/config.yml ~/.claude/config-deep.yml  # Opus model

# Then edit each for different settings
```

## Troubleshooting

### "API key not set" error
```bash
/config set api_key sk-ant-YOUR_KEY
/config save
```

### "sqlite3 gem not available" warning
```bash
gem install sqlite3 --no-document
# Or continue without - sessions won't persist, but CLI still works
```

### Connection test failed
- Check internet connection
- Verify API key is correct
- Check if firewall blocks api.anthropic.com

### Rate limit errors
- The CLI automatically retries with backoff
- Wait a few seconds between requests
- Consider upgrading API plan

### Streaming issues
```bash
/stream  # Turn off streaming
# Or in config:
/config set stream false
```

## Keyboard Shortcuts

- **Ctrl+D**: Exit (same as `/quit`)
- **Ctrl+C**: Cancel current input (not exit)
- **Up/Down arrows**: Navigate command history (Readline)

## Security Notes

- Config file stored at `~/.claude/config.yml` with 0600 permissions
- Sessions stored at `~/.claude/sessions.db` with 0600 permissions
- API key never logged (even in debug mode)
- OpenBSD: Automatic pledge support for syscall restrictions

## Next Steps

1. **Read the full README**: See `README_CLI.md` for all features
2. **Try the examples**: Practice with the workflows above
3. **Customize your setup**: Adjust model, temperature, tokens for your needs
4. **Organize your sessions**: Use tags and search to find past conversations

## Getting Help

- In the CLI: `/help`
- Full documentation: `README_CLI.md`
- Report issues: Create a GitHub issue
- Test suite: Run `ruby test_cli.rb`

Happy chatting! 🚀
