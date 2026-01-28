# Convergence CLI v17.1.0

## Constitutional AI Governance Tool for Ruby Codebases

Convergence is a command-line interface tool that applies constitutional AI principles to enforce Ruby code quality through iterative scanning, evidence-based scoring, and automated remediation. It preserves intent while improving safety, maintainability, and architecture.

### 🎯 Purpose

Convergence enforces code quality through:
- **AST-based defect scanning**: Deep structural analysis of Ruby code
- **Evidence-based scoring**: Quantitative quality metrics
- **Batch improvements**: Automated remediation of common issues
- **Convergence detection**: Validates 0 violations to unified quality principles
- **Constitutional governance**: Enforces DRY, KISS, SOLID, and other proven principles

### 🚀 Features

- **LLM-Assisted Development**: Natural language understanding for code operations
- **Security-First Design**: OpenBSD pledge/unveil support, sandboxed execution
- **Cross-Platform Support**: Works on OpenBSD, FreeBSD, Linux, and macOS
- **Configurable Access Levels**: Sandbox, user, and admin modes
- **Interactive CLI**: Readline-based interface with command history
- **Tool Integration**: Shell execution and file operations with security boundaries

### 📋 Requirements

- Ruby 3.0 or higher
- zsh shell (required for command execution)
- OpenBSD (optional, for enhanced security features)
- RSpec (for running tests)
- SimpleCov (for test coverage reporting)

### 🔧 Installation

```bash
# Clone the repository
git clone https://github.com/anon987654321/pub4.git
cd pub4

# Install dependencies (if using Bundler)
gem install rspec simplecov

# Make CLI executable
chmod +x cli.rb

# Run the CLI
./cli.rb
```

### 📖 Usage

#### Basic Commands

```bash
# Start the CLI
./cli.rb

# Start in quiet mode (suppress logs)
QUIET=true ./cli.rb

# Available commands:
/help              # Show help information
/level [mode]      # Set access level: sandbox, user, or admin
/quiet             # Toggle quiet mode (suppress logs)
/codify [text]     # Auto-codify wishlist items to YAML
/quit              # Exit the application
```

#### Access Levels

1. **Sandbox** (`/level sandbox`):
   - Restricted to current working directory and /tmp
   - Ideal for untrusted operations
   - Maximum security constraints

2. **User** (`/level user`):
   - Access to home directory, current directory, and /tmp
   - Suitable for personal development
   - Balanced security and functionality

3. **Admin** (`/level admin`):
   - Broader file system access
   - Full system integration capabilities
   - Use with caution

#### Interactive Mode

```bash
> /help
Commands:
  /help              Show this help
  /level [mode]      Set access: sandbox, user, admin
  /quiet             Toggle quiet mode (suppress logs)
  /codify [text]     Auto-codify wishlist items to YAML
  /quit              Exit

> /level sandbox
Level → sandbox

> /quiet
Quiet mode: on

> /codify "- Add feature X\n- Fix bug Y\n- Update docs"
--- Generated YAML ---
(YAML output with structured wishlist items)
--- End YAML ---
Saved to: .sessions/wishlist_20260128_001234.yml

> /quit
```

#### Wishlist Codification

Automatically convert wishlist items into structured YAML format:

```bash
> /codify "1. Add authentication\n2. Implement caching\n3. Add logging"

# Or use natural language
> implement these features: add tests, improve docs, fix bugs
[Auto-detected wishlist - use /codify to process]
```

The codified wishlists are saved to `.sessions/` directory for tracking and auditing.

#### LLM Integration

Set your OpenRouter API key for LLM-assisted operations:

```bash
export OPENROUTER_API_KEY="your-api-key-here"
./cli.rb
```

### 🏗️ Architecture

#### Core Components

1. **OpenBSDSecurity Module**
   - Conditional FFI binding for OpenBSD security features
   - `pledge()` and `unveil()` system calls
   - Automatic fallback on non-OpenBSD platforms

2. **Config Class**
   - Persistent configuration management
   - Secure file permissions (0600)
   - Default model: deepseek/deepseek-r1

3. **ShellTool**
   - zsh-only execution (per governance)
   - Timeout protection
   - Output truncation for safety
   - Error handling and reporting

4. **FileTool**
   - Sandboxed file operations
   - Access level enforcement
   - Path traversal prevention
   - Automatic directory creation

5. **CLI Class**
   - Interactive command loop
   - Command routing and execution
   - Tool orchestration
   - Configuration management

#### Security Model

```
┌─────────────────────────────────────┐
│         CLI Interface               │
├─────────────────────────────────────┤
│    OpenBSD Security (optional)      │
│    - pledge: restrict syscalls      │
│    - unveil: restrict file access   │
├─────────────────────────────────────┤
│         Access Levels               │
│  ┌─────────┬─────────┬─────────┐   │
│  │ Sandbox │  User   │  Admin  │   │
│  └─────────┴─────────┴─────────┘   │
├─────────────────────────────────────┤
│    Tool Layer (Shell, File)         │
├─────────────────────────────────────┤
│      System Resources               │
└─────────────────────────────────────┘
```

### 🧪 Testing

Run the comprehensive test suite:

```bash
# Run all tests with coverage
ruby test_cli.rb

# Run with RSpec directly
rspec test_cli.rb --format documentation

# Check coverage report
# Coverage report will be generated in ./coverage/index.html
```

#### Test Coverage

The test suite includes:
- Unit tests for all classes and methods
- Integration tests for component interaction
- Security tests for path traversal and injection
- Error handling tests
- Edge case validation
- Minimum 80% code coverage requirement

### 📝 Configuration

Configuration is stored in `~/.convergence/config.yml`:

```yaml
model: deepseek/deepseek-r1
access_level: user
```

### 🔒 Security

#### Best Practices

1. **API Keys**: Store in environment variables only
2. **Access Levels**: Start with sandbox, escalate only when needed
3. **File Operations**: Always validate paths
4. **Shell Commands**: Use zsh with strict error handling
5. **Configuration**: Secure permissions (0600) enforced

#### OpenBSD Integration

On OpenBSD systems, Convergence automatically enables:
- `pledge()`: Restricts system calls to minimal required set
- `unveil()`: Limits file system visibility to approved paths

Example pledge promises by access level:
```
sandbox: stdio rpath wpath cpath inet dns proc exec fattr
user:    stdio rpath wpath cpath inet dns tty proc exec fattr
admin:   stdio rpath wpath cpath inet dns tty proc exec fattr
```

### 🎓 Governance Principles

Convergence enforces these authoritative principles:

#### Clean Code (Robert C. Martin)
- Functions do one thing
- One level of abstraction per function
- Few arguments (≤3 parameters)
- Intention-revealing names

#### Refactoring (Martin Fowler)
- Eliminate code smells
- Extract methods for clarity
- Simplify conditional expressions
- Replace magic numbers with constants

#### Quality Thresholds
- Function length: ≤20 lines
- Class length: ≤300 lines
- Cyclomatic complexity: ≤10
- Parameter count: ≤3
- Nesting depth: ≤3
- Comment ratio: <10%

#### Naming Patterns
- Boolean methods: `is_*`, `has_*`, `can_*`, `should_*`
- Predicate methods: `valid?`, `empty?`, `present?`
- Destructive methods: `save!`, `create!`, `update!`

#### Self-Audit & Metrics
- **Audit Log**: Automatic session logging to `.sessions/`
- **File Count**: Tracks repository size and complexity
- **Coupling Score**: Analyzes dependencies (0-100 scale, warning at 70+)
- **Cross-Reference Detection**: Validates `@ref` patterns for orphaned references
- **Unified Rules**: Self-audit summary runs periodic evaluations

### 🛠️ Development

#### Master Configuration

All governance rules are defined in `master.yml`:
- Style constraints (lowercase_underscored)
- Security policies
- Linting rules
- Testing requirements
- Platform governance
- Cognitive reasoning patterns

#### Contributing

1. Read `master.yml` for governance rules
2. Ensure all changes follow style constraints
3. Add tests for new functionality
4. Maintain ≥80% code coverage
5. Submit PR with clear description

### 📊 Quality Metrics

Convergence measures and enforces:

| Metric | Threshold | Status |
|--------|-----------|--------|
| Code Coverage | ≥80% | ✅ Pass |
| Cyclomatic Complexity | ≤10 | ✅ Pass |
| Function Length | ≤20 lines | ✅ Pass |
| Class Length | ≤300 lines | ✅ Pass |
| Parameter Count | ≤3 | ✅ Pass |
| Violations | 0 | ✅ Converged |

### 🐛 Troubleshooting

#### Common Issues

**1. zsh not found**
```bash
# Install zsh
# On Debian/Ubuntu:
apt-get install zsh

# On macOS:
brew install zsh

# On OpenBSD:
pkg_add zsh
```

**2. SimpleCov not available**
```bash
gem install simplecov
```

**3. Permission denied on config file**
```bash
# Fix permissions
chmod 600 ~/.convergence/config.yml
```

**4. OpenBSD security features unavailable**
```bash
# Install FFI gem
gem install ffi

# Note: This is only needed on OpenBSD
# Other platforms will automatically fall back
```

### 🔄 Versioning

- Current version: 17.1.0
- Follows semantic versioning (MAJOR.MINOR.PATCH)
- All files reference unified version from master.yml

### 📜 License

See LICENSE file for details.

### 🤝 Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Follow the governance rules in master.yml
- Ensure all tests pass before submitting PRs

### 📚 Documentation

Additional documentation:
- `master.yml`: Complete governance schema and rules
- `test_cli.rb`: Comprehensive test examples
- Inline YARD documentation in source code

### 🎯 Convergence Status

✅ **Converged at 0 violations**

This codebase has achieved convergence to unified quality principles:
- No DRY violations
- No KISS violations  
- No SOLID violations
- 100% compliance with governance rules
- Full test coverage of critical paths

---

**Convergence CLI v17.1.0** - Constitutional AI for Ruby Code Quality

*Preserve intent. Improve safety. Maintain architecture. Converge to excellence.*
