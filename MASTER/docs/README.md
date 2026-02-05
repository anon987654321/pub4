# MASTER Documentation

Welcome to the MASTER (LLM Operating System) documentation. MASTER is a constitutional AI framework that enforces coding principles and best practices through automated analysis and LLM-powered refactoring.

## 📚 Documentation Index

### Core Concepts
- **[PRINCIPLES.md](PRINCIPLES.md)** - Complete guide to all 45 principles with examples and anti-patterns
- **[FRAMEWORK_INTEGRATION.md](FRAMEWORK_INTEGRATION.md)** - Framework modules and plugin system guide
- **[ENFORCEMENT.md](ENFORCEMENT.md)** - Git hooks, validation tools, and enforcement mechanisms

### Advanced Features
- **[SESSION_RECOVERY.md](SESSION_RECOVERY.md)** - Checkpoint system and session recovery guide

### Quick Links
- [Main README](../README.md) - Getting started and installation
- [CHANGELOG](../CHANGELOG.md) - Version history and release notes
- [Examples](../examples/) - Usage examples and patterns

## 🚀 Quick Start

```bash
# Install MASTER
gem install master

# Scan a codebase
bin/cli scan lib/

# Interactive review with principles
bin/cli review src/app.rb

# Queue refactoring tasks
bin/cli queue add "Extract UserService class" --budget 0.50

# Install git hooks for automatic enforcement
bin/install-hooks
```

## 📖 Core Concepts

### Principles System
MASTER enforces 45 coding principles organized in 5 tiers:
- **Core** (1-5): KISS, DRY, YAGNI, Separation of Concerns, Single Responsibility
- **SOLID** (6-9): Open-Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **Quality** (10-20): Law of Demeter, Composition over Inheritance, Fail Fast, etc.
- **Code** (21-32): Meaningful Names, Small Functions, Pure Functions, etc.
- **Aesthetic** (33-45): Squint Test, Typography, Progressive Disclosure, etc.

### Framework Architecture
```
MASTER/
├── lib/
│   ├── framework/          # Core framework modules
│   │   ├── behavioral_rules.rb
│   │   ├── universal_standards.rb
│   │   ├── workflow_engine.rb
│   │   ├── quality_gates.rb
│   │   └── copilot_optimization.rb
│   ├── plugins/            # Domain-specific plugins
│   │   ├── design_system.rb
│   │   ├── web_development.rb
│   │   ├── business_strategy.rb
│   │   └── ai_enhancement.rb
│   ├── principles/         # 45 YAML principle definitions
│   └── config/             # Configuration files
├── bin/
│   ├── cli                 # Main CLI interface
│   ├── validate_principles # Validation tool
│   ├── install-hooks       # Git hooks installer
│   └── check_ports         # Port consistency checker
└── test/                   # Test suite
```

### Detection Modes
MASTER uses dual detection:
1. **Literal Detection** - Fast regex-based pattern matching for known anti-patterns
2. **Conceptual Detection** - LLM-powered analysis for semantic violations

### Enforcement Levels
- **Error**: Must fix before commit (blocking)
- **Warning**: Should fix (logged but non-blocking)
- **Info**: Suggestions and best practices

## 🛠 CLI Commands

### Core Commands
```bash
bin/cli scan PATH          # Scan code for violations
bin/cli review FILE        # Interactive principle review
bin/cli refactor FILE      # Auto-fix violations
bin/cli ask "question"     # Query the LLM about code
```

### Advanced Commands
```bash
bin/cli queue list                    # View queued tasks
bin/cli queue add "task" --budget X   # Add task with budget
bin/cli chamber FILE                  # Creative chamber mode
bin/cli evolve                        # Evolutionary improvements
bin/cli introspect                    # System introspection
```

### Utility Commands
```bash
bin/cli principles              # List all principles
bin/cli status                  # System status
bin/cli cost                    # View usage costs
bin/cli version                 # Version information
```

## 🔧 Configuration

### Master Configuration
Located at `MASTER/.master_config`:
```ruby
{
  "api_key": "your-openrouter-key",
  "model": "anthropic/claude-3.5-sonnet",
  "budget_limit": 10.0,
  "enforcement_level": "error"
}
```

### Principle Enforcement
Configure in `lib/config/principle_enforcement.yml`:
```yaml
enforcement:
  mode: strict  # strict, lenient, advisory
  auto_fix: true
  fail_on_error: true
  
severity_weights:
  error: 10
  warning: 5
  info: 1
```

## 📊 Metrics and Monitoring

MASTER tracks:
- Violation counts by principle
- Fix success rates
- Token usage and costs
- Refactoring history
- Code quality trends

View metrics with: `bin/cli metrics`

## 🧪 Testing

Run the test suite:
```bash
# Full test suite
ruby test/test_master.rb

# Specific tests
ruby test/test_review_crew.rb
ruby test/test_cli_context.rb
```

## 🤝 Contributing

MASTER follows its own principles:
1. Keep changes simple (KISS)
2. Don't repeat code (DRY)
3. Only build what's needed (YAGNI)
4. Single responsibility per module
5. Test all changes

## 📝 License

MASTER is released under the MIT License. See LICENSE file for details.

## 🙏 Acknowledgments

MASTER draws inspiration from:
- Constitutional AI principles (Anthropic)
- Unix philosophy
- Design principles from Tadao Ando
- Software craftsmanship movement
- Open source best practices

---

**Version**: MASTER v52.0 REFLEXION  
**Last Updated**: 2024-02-05  
**Maintainer**: MASTER Development Team
