# Functional Core, Imperative Shell

> Pure logic in the core, side effects at the edges.

tier: architecture
priority: 17
auto_fixable: false

## Anti-patterns (violations)

### scattered_side_effects
- **Smell**: IO/DB calls deep in business logic
- **Example**: `calculate_price()` that logs to file
- **Fix**: Return data from core, let shell handle IO

### impure_core
- **Smell**: Core functions depend on global state
- **Example**: Business logic reading ENV variables
- **Fix**: Inject configuration, keep core deterministic
