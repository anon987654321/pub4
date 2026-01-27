# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [17.1.0] - 2026-01-22

### Added
- OpenBSD security module with FFI bindings for pledge/unveil
- Sandboxed file operations with access level enforcement
- Interactive CLI with Readline support
- Configuration persistence with secure permissions
- Shell tool with zsh-only execution
- Comprehensive test suite with 80%+ coverage

### Changed
- Updated governance to version 17.0.0
- Improved error handling across all modules
- Enhanced security boundaries for file and shell operations

### Security
- API keys restricted to environment variables only
- Automatic secrets detection in commits
- Path traversal prevention in FileTool
- Command injection protection in ShellTool

## [17.0.0] - 2026-01-22

### Added
- Initial release of quality governance system
- Comprehensive master.yml with governance rules
- Style constraints (lowercase_underscored)
- Comment policy and documentation requirements
- Schema governance with single source of truth
- Execution truth verification requirements
- Security policies (API keys, secrets detection, pledge/unveil)
- Linting rules for Ruby, YAML, and zsh
- Version governance with semantic versioning
- Platform governance (OpenBSD primary)
- Code quality rules and thresholds
- Testing requirements and principles
- Cognitive reasoning framework
- Epistemic humility guidelines
- Contradiction detection system
- Self-improvement protocols
- Temporal coherence for session continuity
- Emergence detection mechanisms
- Recursive governance for codebase traversal
- Extreme mode for strict quality enforcement
- Meta exceptions for edge cases

### Documentation
- Created comprehensive README.md
- Added inline documentation with YARD format
- Established documentation requirements

[17.1.0]: https://github.com/anon987654321/pub4/releases/tag/v17.1.0
[17.0.0]: https://github.com/anon987654321/pub4/releases/tag/v17.0.0
