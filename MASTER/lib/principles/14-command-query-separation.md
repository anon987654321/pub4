# Command-Query Separation

> Methods should either change state OR return data, never both.

tier: design
priority: 14
auto_fixable: true

## Anti-patterns (violations)

### side_effects_in_queries
- **Smell**: Getter modifies state
- **Example**: `stack.pop()` returns value AND removes it
- **Fix**: Split: `stack.top()` + `stack.remove()`

### mixed_responsibilities
- **Smell**: Method both computes and persists
- **Example**: `calculate_total()` that also saves to DB
- **Fix**: `total = calculate(); save(total)`
