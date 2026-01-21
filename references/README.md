# Reference Materials

This directory contains reference documentation for extending master.yml with domain-specific expertise.

## Contents

### Typography
- **__bringhurst-typography-rules.yml** - Principles from "The Elements of Typographic Style" by Robert Bringhurst
  - Optimal line length, spacing, rhythm, and proportion
  - CSS implementation patterns

### Code Quality
- **__clean-code-master-integration.yml** - Integration guide for Clean Code principles into master.yml
  - How to enforce quality rules systematically
  - Thresholds and metrics

- **__clean-code-refactoring-rules.yml** - Clean Code + Refactoring principles
  - From Robert C. Martin's "Clean Code"
  - From Martin Fowler's "Refactoring"
  - Naming, functions, classes, error handling

### Writing
- **__elements-of-style-rules.yml** - Writing principles from Strunk & White's "The Elements of Style"
  - Grammar rules, composition, style
  - Clarity and conciseness

### Rails/Hotwire
- **__rails_hotwire_extension.txt** - Modern Rails patterns
  - Hotwire, Turbo, Stimulus
  - View consolidation, semantic HTML
  - Reactive patterns

### Solidus E-Commerce
- **__solidus_production_guide.txt** - Solidus production deployment guide
- **__solidus_retrofit_guide.txt** - Retrofitting Solidus into existing applications

## Usage

These files are reference materials. They should NOT be deleted or modified without careful consideration.
They provide domain expertise that extends the core master.yml governance framework.

To integrate principles from these files:
1. Read and understand the relevant reference file
2. Extract applicable patterns for your context
3. Apply to your code with adaptations as needed
4. Do NOT blindly copy - understand and adapt

## File Naming Convention

The `__` prefix indicates these are reference/configuration files that:
- Should not be executed directly
- Provide foundational knowledge
- Extend core governance rules
- Are stable and rarely change
