# Convergence CLI

A lightweight, zero-dependency command-line interface for interacting with multiple LLM providers (OpenRouter, Anthropic, OpenAI) with integrated governance via `master.yml`.

## Features

- **Zero gem dependencies**: Pure Ruby stdlib only
- **Multi-provider support**: OpenRouter (primary), Anthropic, OpenAI
- **master.yml integration**: Governance rules, banned tools, anti-truncation validation
- **Filesystem tools**: Sandboxed read/write/search with SHA256 verification
- **Streaming responses**: Real-time output from LLMs
- **Secure configuration**: API keys stored with 0600 permissions in `~/.convergence/config.yml`

## Installation

### Prerequisites

- Ruby 2.7 or higher
- Internet connection (for API calls)

### OpenBSD Installation

```bash
# Install Ruby (if not already installed)
doas pkg_add ruby

# Clone the repository
git clone https://github.com/anon987654321/pub4.git
cd pub4

# Make CLI executable
chmod +x cli.rb

# Run setup wizard
ruby cli.rb --init
```

### Other Unix-like Systems

```bash
# Clone the repository
git clone https://github.com/anon987654321/pub4.git
cd pub4

# Make CLI executable
chmod +x cli.rb

# Run setup wizard
./cli.rb --init
```

## Setup Wizard

On first run with `--init`, the setup wizard guides you through configuration:

1. **Select Provider**: Choose from OpenRouter, Anthropic, or OpenAI
2. **Enter API Key**: Provide your API key (stored securely with 0600 permissions)
3. **Configuration Saved**: Settings saved to `~/.convergence/config.yml`

### Getting API Keys

| Provider | URL | Notes |
|----------|-----|-------|
| OpenRouter | https://openrouter.ai/keys | Unified access to multiple models |
| OpenAI | https://platform.openai.com/api-keys | Direct OpenAI access |
| Anthropic | https://console.anthropic.com/settings/keys | Direct Anthropic access |

## Usage

### Interactive Mode

```bash
ruby cli.rb
```

Start an interactive session where you can chat with the LLM and use commands.

### Direct Query Mode

```bash
ruby cli.rb "What is the capital of France?"
```

Send a single query and get a response without entering interactive mode.

### Show master.yml Status

```bash
ruby cli.rb --master
```

Display the current master.yml governance rules and configuration.

## Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/model NAME` | Switch to a different model |
| `/clear` | Clear conversation history |
| `/tree [PATH]` | Show directory tree (default: current directory) |
| `/read PATH` | Read a file with SHA256 hash |
| `/master` | Show master.yml governance status |
| `/config` | Show current configuration |
| `/reset` | Reset configuration and reconfigure |
| `exit` or `quit` | Exit the CLI |

## Model Comparison

### OpenRouter (Recommended)

OpenRouter provides unified access to multiple models through a single API:

| Short Name | Full Model ID | Use Case |
|------------|---------------|----------|
| `deepseek-r1` | `deepseek/deepseek-r1` | General purpose, reasoning |
| `claude-3.5` | `anthropic/claude-3.5-sonnet` | Code analysis, writing |
| `gpt-4o` | `openai/gpt-4o` | General purpose |
| `gemini-2.0` | `google/gemini-2.0-flash-exp` | Fast responses |

### Anthropic Direct

| Short Name | Full Model ID | Use Case |
|------------|---------------|----------|
| `claude-opus-4` | `claude-opus-4-20250514` | Most capable |
| `claude-sonnet-4` | `claude-sonnet-4-20250514` | Balanced |
| `claude-3.5` | `claude-3-5-sonnet-20241022` | Fast, capable |

### OpenAI Direct

| Short Name | Full Model ID | Use Case |
|------------|---------------|----------|
| `gpt-4o` | `gpt-4o` | Most capable |
| `gpt-4o-mini` | `gpt-4o-mini` | Fast, efficient |
| `gpt-4-turbo` | `gpt-4-turbo-preview` | Latest features |

## master.yml Governance

The CLI integrates deeply with `master.yml` for quality governance:

### Banned Tools Enforcement

Commands using banned tools (python, bash, sed, awk, grep, wc, head, tail, sudo) are blocked:

```ruby
# When you try to run a banned tool:
> shell(command: "python script.py")
{
  error: "BLOCKED by master.yml: python",
  alternative: "use ruby"
}
```

### Anti-Truncation Validation

Responses are validated against truncation patterns defined in master.yml:

```yaml
anti_truncation:
  forbidden: ["...", "rest_of_code", "[truncated]", "todo:", "fixme:"]
```

If an LLM response contains these patterns, an error is raised to prevent incomplete code.

### Golden Rule Integration

The golden rule from master.yml is injected into the system prompt:

```
Golden Rule: preserve_then_improve_never_break
```

### Thresholds

Quality thresholds are enforced:

- Functions: ≤20 lines
- Nesting: ≤3 levels
- These are communicated to the LLM in the system prompt

## Filesystem Tools

All filesystem operations are sandboxed to the current directory and provide security features:

### read(path)

Read a file with SHA256 verification:

```
/read master.yml
```

Output includes:
- Path
- SHA256 hash
- File size
- Content (up to 50KB)

### tree(path, max_depth)

Display directory structure:

```
/tree .
```

Shows files and directories in a tree format (default depth: 3).

### search(query, path)

Search for text in files:

```ruby
# Using in conversation:
"Search for 'def initialize' in all Ruby files"
```

### shell(command)

Execute shell commands (subject to master.yml restrictions):

```ruby
# Safe commands work:
shell(command: "ls -la")

# Banned commands are blocked:
shell(command: "python script.py")
# => { error: "BLOCKED by master.yml: python", alternative: "use ruby" }
```

## Security

### API Key Storage

- API keys stored in `~/.convergence/config.yml`
- File permissions set to `0600` (user read/write only)
- Keys never logged or displayed

### Sandbox Enforcement

All filesystem operations are restricted to the current directory:

```ruby
# Allowed:
read(path: "file.txt")
read(path: "./subdir/file.txt")

# Blocked:
read(path: "/etc/passwd")
# => { error: "Access denied: /etc/passwd outside sandbox" }
```

### Dangerous Pattern Blocking

The following patterns are automatically blocked in shell commands:

- `rm -rf /`, `rm -rf /*`, `rm -rf ~`
- `> /etc/passwd`, `> /etc/shadow`, `> /etc/sudoers`
- `| sh`, `| bash`
- `curl | sh`, `wget | sh`

### SHA256 Verification

All file reads include SHA256 hashes for content verification:

```
Path: cli.rb
SHA256: a1b2c3d4e5f6...
Size: 28394 bytes
```

## Examples

### Rails Development Workflow

```bash
# Start interactive session
ruby cli.rb

# Explore the project
/tree app/models

# Read a specific file
/read app/models/user.rb

# Ask about the code
> Explain the associations in app/models/user.rb

# Get file tree context
> Show me all controllers and their routes
```

### Code Analysis

```bash
# Direct query for quick analysis
ruby cli.rb "Analyze the user authentication flow in this Rails app"
```

### Debugging

```bash
# Start session
ruby cli.rb

# Read error logs
/read log/development.log

# Ask for help
> I'm getting a N+1 query warning. Can you help me fix it?
```

## Configuration File

Location: `~/.convergence/config.yml`

```yaml
provider: openrouter
model: deepseek/deepseek-r1
api_keys:
  openrouter: sk-or-v1-...
  anthropic: sk-ant-api...
```

## Troubleshooting

### "Not configured" Error

Run the setup wizard:

```bash
ruby cli.rb --init
```

### API Errors

Check your API key:

```
/config
```

Update if needed:

```
/reset
ruby cli.rb --init
```

### master.yml Not Found

The CLI searches for master.yml in these locations:

1. `~/pub/master.yml`
2. `./master.yml` (current directory)
3. Same directory as `cli.rb`

Create `master.yml` in one of these locations or the governance features will be disabled.

## Development

### Project Structure

```
cli.rb                  # Single consolidated CLI
master.yml             # Governance rules
~/.convergence/        # User configuration
  config.yml          # API keys and settings (0600 permissions)
```

### Architecture

The CLI is organized into focused classes:

- **MasterConfig**: Loads and enforces master.yml rules
- **Config**: User configuration management
- **APIClient**: Multi-provider API client with streaming
- **FileSystem**: Sandboxed filesystem tools
- **ContextBuilder**: System prompt generation
- **ToolExecutor**: JSON tool call execution
- **UI**: Terminal interface helpers
- **CLI**: Main interactive loop

### Zero Dependencies

The CLI uses only Ruby stdlib:

- `json` - JSON parsing
- `yaml` - Configuration files
- `net/http` - API requests
- `uri` - URL handling
- `fileutils` - File operations
- `open3` - Shell command execution
- `timeout` - Command timeouts
- `digest` - SHA256 hashing
- `io/console` - Password input

## Contributing

Contributions are welcome! Please ensure:

1. No external gem dependencies
2. Follow master.yml governance rules
3. Maintain security best practices
4. Test on OpenBSD and other Unix-like systems

## License

[Your license here]

## Support

For issues or questions:

- GitHub Issues: https://github.com/anon987654321/pub4/issues
- Discussion: [Link to discussions]

## Changelog

### v2.0 (Current)

- Consolidated multi-file CLI into single `cli.rb`
- Zero gem dependencies (pure stdlib)
- Deep master.yml integration
- Multi-provider API support (OpenRouter, Anthropic, OpenAI)
- Sandboxed filesystem tools
- Streaming responses
- SHA256 verification for files
- Secure API key storage (0600 permissions)
