# DRY (Don't Repeat Yourself)

> Every piece of knowledge must have a single, authoritative representation.

tier: core
priority: 2
auto_fixable: true

## Anti-patterns (violations)

### duplicate_code
- **Smell**: Same logic in multiple places
- **Example**: Identical validation in 3 controllers
- **Fix**: Extract to shared method/module

### copy_paste_programming
- **Smell**: Copying code instead of abstracting
- **Example**: Cloning a function and changing variable names
- **Fix**: Parameterize the original, reuse it
