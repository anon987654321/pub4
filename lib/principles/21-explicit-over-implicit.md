# Explicit Over Implicit

> Zen of Python. Clarity over magic.

tier: clarity
priority: 21
auto_fixable: true

## Anti-patterns (violations)

### magic_values
- **Smell**: Unexplained literals in code
- **Example**: `if status == 7` - what is 7?
- **Fix**: Use constants: `STATUS_APPROVED = 7`

### hidden_behavior
- **Smell**: Implicit conversions or callbacks
- **Example**: Rails `before_save` modifying data silently
- **Fix**: Make transformations explicit in code path

### implicit_conversions
- **Smell**: Type coercion without explicit cast
- **Example**: `"5" + 3` behavior varies by language
- **Fix**: Explicit: `int("5") + 3`
