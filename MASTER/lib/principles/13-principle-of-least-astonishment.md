# Principle of Least Astonishment

> Systems should behave as users expect. No surprises.

tier: ux
priority: 13
auto_fixable: false

## Anti-patterns (violations)

### surprising_behavior
- **Smell**: Method does something unexpected from its name
- **Example**: `save()` that also sends email notification
- **Fix**: Rename or split: `save_and_notify()`

### inconsistent_api
- **Smell**: Similar methods behave differently
- **Example**: `find` returns nil, `get` raises exception
- **Fix**: Establish conventions, document behavior

### hidden_side_effects
- **Smell**: Getter that modifies state
- **Example**: `get_value()` that increments counter
- **Fix**: Separate query from command
