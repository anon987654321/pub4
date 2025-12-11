# Claude CLI Tool

Interactive command-line interface for Claude AI with streaming support, session management, and enhanced error handling.

## Features

- **Streaming Support**: Real-time SSE (Server-Sent Events) streaming with typewriter effect
- **Enhanced Error Handling**: Automatic retry logic with exponential backoff for transient errors
- **Session Management**: SQLite-based session storage with metadata tracking
- **Master.yml Validation**: Schema validation for configuration files
- **Configuration Validation**: Validates model names, temperature, tokens, and API settings
- **OpenBSD Optimizations**: Pledge support for enhanced security
- **Zero Dependencies**: Uses Ruby stdlib only (except optional sqlite3 gem for persistence)

## Installation

### Requirements

- Ruby 2.7+ (3.0+ recommended)
- OpenBSD 7.4+, Linux (Ubuntu 22.04+), or macOS 13.0+
- SQLite3 gem (optional, for session persistence)

### Install SQLite3 gem (optional)

```bash
gem install sqlite3 --no-document
```

Without SQLite3, the CLI will still work but sessions won't be persisted.

### Make executable

```bash
chmod +x cli.rb
```

## Configuration

Configuration is stored in `~/.claude/config.yml` and created on first run.

### Set API Key

```bash
./cli.rb
# In the CLI:
/config set api_key YOUR_API_KEY_HERE
/config save
```

Or edit `~/.claude/config.yml` directly:

```yaml
api_key: YOUR_API_KEY_HERE
api_base: https://api.anthropic.com
model: claude-3-5-sonnet-20241022
max_tokens: 4096
temperature: 1.0
stream: true
debug: false
```

### Configuration Options

- `api_key`: Your Claude API key (required)
- `api_base`: API endpoint URL (default: https://api.anthropic.com)
- `model`: Claude model to use (validates against known models)
- `max_tokens`: Maximum response tokens (1-200,000)
- `temperature`: Sampling temperature (0.0-1.0)
- `stream`: Enable streaming responses (true/false)
- `debug`: Enable debug logging (true/false)

## Usage

### Start the CLI

```bash
./cli.rb
```

### Basic Chat

```
You: What is the capital of France?
Claude: The capital of France is Paris.
```

### Slash Commands

#### Message Commands

```bash
/clear              # Clear conversation history
```

#### Streaming

```bash
/stream             # Toggle streaming on/off
```

#### Configuration

```bash
/config list        # Show current configuration
/config get model   # Get specific config value
/config set model claude-3-5-haiku-20241022  # Set config value
/config save        # Save configuration to disk
/config validate    # Validate current configuration
```

#### Model Settings

```bash
/model                          # Show current model
/model claude-3-5-haiku-20241022  # Set model
/tokens                         # Show max_tokens
/tokens 8192                    # Set max_tokens
/temp                           # Show temperature
/temp 0.7                       # Set temperature
```

#### Master.yml Validation

```bash
/master validate    # Validate master.yml schema
```

The validator checks:
- Required fields (meta.version, principles.critical)
- Deprecated fields
- File structure and syntax
- Generates SHA256 checksum

#### Session Management

```bash
/session info              # Show current session info
/session list              # List recent sessions
/session load 5            # Load previous session by ID
/session search "topic"    # Search sessions by content
/session tag production    # Add tag to current session
```

Session metadata includes:
- Total token usage
- Total estimated cost
- Average response time
- Master.yml checksum
- Custom tags for organization

#### Other Commands

```bash
/help               # Show help
/quit, /exit        # Exit the CLI
```

### Streaming Examples

When streaming is enabled (default), you'll see responses appear character-by-character:

```
You: Write a haiku about Ruby
Claude: Code flows like water,
Elegant syntax, joy blooms,
Ruby's heart beats true.
```

Toggle streaming mid-session:

```
/stream             # Turns off streaming
You: Quick question
Claude: [Full response appears at once]

/stream             # Turns streaming back on
You: Another question
Claude: [Response streams in real-time]
```

## Error Handling

The CLI handles various error conditions with actionable messages:

### Authentication Errors

```
AuthenticationError: Invalid API key. Run: claude config set api_key YOUR_KEY
```

### Rate Limiting

Automatically retries with exponential backoff:

```
[DEBUG] Rate limited (429), retrying in 1.0s...
[DEBUG] Rate limited (429), retrying in 2.0s...
```

### Server Errors

```
ServerError: Server error (503): Service unavailable. Try again later.
```

### Timeout Errors

```
TimeoutError: Request timed out after 3 attempts. Try again later.
```

### Network Errors

Transient errors (connection reset, connection refused) are automatically retried up to 3 times with exponential backoff.

## Session Management

Sessions are stored in `~/.claude/sessions.db` (SQLite3 required).

### Session Metadata

Each session tracks:

- **Total tokens**: Cumulative token usage across all messages
- **Total cost**: Estimated API cost (approximate)
- **Response times**: Individual response times for calculating averages
- **Master checksum**: SHA256 of master.yml at session creation (detects config drift)
- **Tags**: Custom labels for organizing sessions
- **Messages**: Full conversation history

### Session Search

Search sessions by content or tags:

```bash
/session search "OpenBSD"
/session search "production"
```

### Session Tagging

Organize sessions with tags:

```bash
/session tag production
/session tag bug-investigation
/session tag code-review
```

## Master.yml Validation

Validates the structure of `master.yml` configuration files.

### Validation Checks

- **Required fields**: meta.version, principles.critical
- **Deprecated fields**: Warns about outdated configuration
- **Syntax**: YAML parsing validation
- **Checksum**: SHA256 hash for tracking changes

### Validation Example

```bash
/master validate

=== Master.yml Validation ===

  ✓ All checks passed
  Checksum: a1b2c3d4e5f6...
```

With errors:

```bash
=== Master.yml Validation ===

Errors:
  ✗ Missing required section: meta
  ✗ Missing required field: principles.critical

Warnings:
  ⚠ Deprecated field found: old_config.field
```

## Configuration Validation

The CLI validates configuration values when setting them:

### Model Validation

```bash
/config set model claude-opus-2024
Warning: 'claude-opus-2024' is not a known Claude model
Known models: claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022, ...
```

### Temperature Validation

```bash
/config set temperature 1.5
Error: Temperature must be between 0.0 and 1.0
```

### Token Validation

```bash
/config set max_tokens -100
Error: max_tokens must be between 1 and 200,000
```

### API Connectivity Testing

After setting credentials, the CLI tests connectivity:

```bash
/config set api_key sk-ant-...
Testing API connection... OK
```

## OpenBSD Optimizations

On OpenBSD, the CLI automatically applies `pledge` restrictions for enhanced security:

```
OpenBSD pledge activated: stdio rpath wpath cpath inet dns tty
```

This restricts system operations to:
- `stdio`: Standard I/O
- `rpath`: Read files
- `wpath`: Write files  
- `cpath`: Create files
- `inet`: Network access
- `dns`: DNS lookups
- `tty`: Terminal I/O

## Debug Mode

Enable debug logging to see detailed information:

```bash
/config set debug true

[DEBUG] Rate limited (429), retrying in 1.0s...
[DEBUG] Failed to parse SSE data: unexpected token
[DEBUG] Connection test failed: timeout
```

## Files and Directories

- `~/.claude/config.yml`: Configuration file (mode 0600)
- `~/.claude/sessions.db`: Session database (mode 0600, SQLite3)

Both files are created with secure permissions to protect API keys and session data.

## Known Claude Models

The CLI validates against these known models:

- claude-3-5-sonnet-20241022 (default)
- claude-3-5-sonnet-20240620
- claude-3-5-haiku-20241022
- claude-3-opus-20240229
- claude-3-sonnet-20240229
- claude-3-haiku-20240307
- claude-sonnet-4-20250514

Unknown model names will show a warning but won't prevent usage (in case of new releases).

## Troubleshooting

### SQLite3 gem missing

```
Warning: sqlite3 gem not available. Sessions will not be persisted.
```

**Solution**: Install the sqlite3 gem:

```bash
gem install sqlite3 --no-document
```

### Configuration errors on startup

```
Configuration errors:
  ✗ API key not set. Use: claude config set api_key YOUR_KEY
```

**Solution**: Set your API key:

```bash
/config set api_key YOUR_API_KEY
/config save
```

### Connection test failed

```
Testing API connection... FAILED
Warning: Could not connect to API. Check your configuration.
```

**Solutions**:
- Verify API key is correct
- Check network connectivity
- Verify api_base URL is correct
- Check firewall settings

### Rate limiting

If you hit rate limits frequently:

1. The CLI automatically retries with exponential backoff
2. Wait a few minutes between requests
3. Consider upgrading your API plan

### Streaming issues

If streaming doesn't work:

```bash
/stream  # Try toggling streaming off
```

Or disable in config:

```bash
/config set stream false
/config save
```

## Security Considerations

- API keys stored with 0600 permissions (owner-only read/write)
- Session database stored with 0600 permissions
- OpenBSD pledge support for syscall restrictions
- HTTPS for all API communication
- No sensitive data in logs (unless debug mode)

## Cost Tracking

Session tracking includes estimated costs:

```bash
/session info

Session Info:
  ID: 1
  Created: 2025-12-11T22:00:00Z
  Updated: 2025-12-11T22:30:00Z
  Total tokens: 12,450
  Total cost: $0.1121
  Avg response time: 2.34s
  Master checksum: a1b2c3d4...
  Tags: production, code-review
  Messages: 8
```

Note: Cost estimates are approximate and based on average pricing. Check Claude's official pricing for accurate costs.

## Platform Support

Tested on:
- OpenBSD 7.4+ (with pledge support)
- Ubuntu 22.04 LTS
- macOS 13.0+

Should work on any platform with Ruby 2.7+ and standard library support.

## Version

Current version: 1.0.0

## License

See repository license.
