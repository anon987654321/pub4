# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Verbose principle descriptions in master.yml with full rationale, examples, and compliance guidance
- JSON export support for governance state, configuration, and metrics via `/export` command
- Migration logic for schema version changes (v1→v2)
- Expanded examples in CLI output and help messages with symbols (✓/✗/⚠)
- Axioms section defining fundamental domain truths (DRY, YAGNI, Law of Demeter, etc.)
- Defect catalog with structured code smell registry (11 defects with detection and remediation)
- Governance class with calculate_weights method for 5-dimensional quality analysis
- GovernanceExporter class for exporting master.yml to JSON
- DecisionSupport module for calculating weighted scores
- UIHandler class for decoupled presentation layer
- Mode awareness integrated into interaction patterns
- Chat codification framework in meta section
- This CHANGELOG.md file
- test_new_features.rb test suite for new functionality

### Changed
- Moved unified_rules to top of rules section for better visibility
- Hoisted constants to top of cli.rb for clarity and maintainability
- Reorganized mode_awareness into interaction section
- Decoupled UI with prompt injection pattern
- Enhanced verbosity in unified_rules explanations
- Refactored CLI class to use UIHandler for presentation
- Improved .gitignore to exclude governance export files
- Updated README.md with comprehensive documentation

### Fixed
- YAML syntax issues in master.yml
- Security regex patterns to avoid false positives
- Catastrophic backtracking in maintainability scoring
- Path validation for export command
- Required 'time' library for iso8601 timestamps
- Ensured 0 violations of governance principles

## [17.1.0] - 2026-01-22

### Added
- Convergence CLI initial release
- OpenBSD security integration with pledge/unveil
- Configurable access levels (sandbox, user, admin)
- ShellTool for zsh command execution
- FileTool with sandboxed file operations
- Interactive readline-based interface
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

[Unreleased]: https://github.com/anon987654321/pub4/compare/v17.1.0...HEAD
[17.1.0]: https://github.com/anon987654321/pub4/releases/tag/v17.1.0
[17.0.0]: https://github.com/anon987654321/pub4/releases/tag/v17.0.0
