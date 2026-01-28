# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [17.1.0] - 2026-01-27

### Changed
- Renamed from "Convergence" to "Master" throughout codebase
- Updated meta.name to "master" in master.yml
- Renamed CLI references and class names from Convergence to Master
- Changed "converged" status to "compliant" for consistency
- Updated "convergence_threshold" to "compliance_threshold"
- Changed config path from ~/.convergence to ~/.master

### Added
- **Critical Opportunities**:
  - Verbose principle descriptions with rationale, violation examples, and remedies
  - JSON export support for CI/CD integration
  - Migration logic for governance schema upgrades
  - Expanded output examples (boot sequence, validation reports, defect output)
  - Axioms section with foundational truths
  - Comprehensive defect_catalog with taxonomy of code issues
  
- **High-Value Opportunities**:
  - Enhanced governance with calculate_weights algorithm
  - Defect scoring system with severity weights
  - Pre-commit and pre-merge validation rules
  
- **Micro Opportunities**:
  - unified_rules section at top of master.yml
  - mode_awareness integrated into interaction patterns
  - Constants section with hoisted thresholds
  - chat_codification in meta section
  - CHANGELOG.md following Keep a Changelog format

### Security
- Maintained security-first design with OpenBSD pledge/unveil support
- Path traversal and SQL injection risk detection in defect_catalog

### Fixed
- Improved code organization and readability
- Enhanced error handling with specific exception types

## [16.0.0] - 2026-01-22

### Added
- Initial quality governance system
- Constitutional AI governance principles
- Security features with OpenBSD support
- Multi-level access control (sandbox, user, admin)

[17.1.0]: https://github.com/anon987654321/pub4/compare/v16.0.0...v17.1.0
[16.0.0]: https://github.com/anon987654321/pub4/releases/tag/v16.0.0
