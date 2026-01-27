# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [17.1.0] - 2026-01-27

### Added
- **CHANGELOG.md**: Created comprehensive version history following Keep a Changelog format
- **Verbose principles**: Expanded principles section with descriptions, rationales, and examples
- **Axioms section**: Foundational truths (DRY, YAGNI, Law of Demeter, etc.)
- **Defect catalog**: Common defects with symptoms, root causes, detection, and fixes
- **JSON export**: `/export json` command to export governance rules
- **GovernanceExporter class**: Exports master.yml to structured JSON
- **DecisionSupport module**: Calculate weighted scores for decision prioritization
- **UIHandler class**: Decoupled UI layer from business logic
- **Migration logic**: Section for managing version upgrades
- **Calculate weights**: Algorithm for prioritizing options based on multiple factors
- **Chat codification**: Process for preserving LLM conversation insights
- **Hoisted constants**: TOP_LEVEL constants for easier reference and maintenance
- **Expanded examples**: Throughout master.yml (linting, boot_sequence, autonomy)
- **test_new_features.rb**: Test suite for new functionality

### Changed
- Reorganized master.yml sections for better logical flow
- Restored verbosity in key sections (less terse, more explanatory)
- Updated README.md with comprehensive documentation of new features
- Improved .gitignore to exclude governance export files
- Refactored CLI class to use UIHandler for presentation

### Fixed
- YAML syntax issues in master.yml
- Required 'time' library for iso8601 timestamps

### Documentation
- Added JSON export usage examples
- Added DecisionSupport usage examples
- Documented axioms and defect catalog
- Expanded governance principles documentation
- Added decision support section to README

## [17.1.0] - 2026-01-22 (Original Release)

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
