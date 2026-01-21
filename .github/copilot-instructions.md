# GitHub Copilot Instructions

This repository uses a comprehensive quality governance system defined in `master.yml` at the root of the repository.

## Key Directives

Before making any changes or suggestions, please:

1. **Read `master.yml`** - This file contains the complete quality governance system for LLM-assisted development
2. **Follow style rules strictly**:
   - Use lowercase_only (no camelCase, PascalCase, or SCREAMING_CASE)
   - Use underscores_between_words (no kebab-case)
   - Use plain_english descriptions
   - Avoid code examples except for zsh patterns
3. **Apply meta-cognitive principles** from master.yml including:
   - Self-observation and self-questioning
   - Causal reasoning for debugging and design
   - Uncertainty calibration and epistemic humility
   - Goal decomposition for complex tasks
4. **Respect banned decorators** - No horizontal rules, section boxes, bracket decorators, or box-drawing characters
5. **Use preferred tools**: Ruby, zsh, and doas (avoid Python, bash, sed, awk, grep, wc, head, tail, sort, find, sudo)
6. **Follow contextual migration rules** when organizing code across files

For the complete ruleset, refer to `master.yml` in the repository root.
