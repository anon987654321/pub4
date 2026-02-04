# Composition Over Inheritance

> Favor object composition over class inheritance. GoF wisdom.

tier: design
priority: 11
auto_fixable: false

## Anti-patterns (violations)

### deep_hierarchy
- **Smell**: Inheritance chain deeper than 3 levels
- **Example**: `Widget < Control < View < Base < Object`
- **Fix**: Flatten with mixins or composition

### refused_bequest
- **Smell**: Subclass ignores or overrides most parent methods
- **Example**: `EmptyList < List` that disables `add`, `remove`
- **Fix**: Use composition: `has_a` not `is_a`

### inheritance_abuse
- **Smell**: Inheriting for code reuse, not substitutability
- **Example**: `Stack < ArrayList` just to reuse methods
- **Fix**: Compose: `Stack` contains `ArrayList`
