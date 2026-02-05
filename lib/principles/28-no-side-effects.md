# No Side Effects

> Functions shouldn't change state they don't own.

tier: functional
priority: 28
auto_fixable: false

## Anti-patterns (violations)

### hidden_side_effects
- **Smell**: Function modifies external state silently
- **Example**: `get_user()` that also updates last_accessed
- **Fix**: Make explicit: `get_user()` + `touch_user()`

### global_mutation
- **Smell**: Function modifies global variables
- **Example**: `calculate()` that sets `$result`
- **Fix**: Return value instead of mutating global
