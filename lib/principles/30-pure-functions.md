# Pure Functions

> Same input, same output. No side effects.

tier: functional
priority: 30
auto_fixable: true

## Anti-patterns (violations)

### impure_functions
- **Smell**: Output depends on hidden state
- **Example**: `calculate()` returns different values based on time
- **Fix**: Pass all dependencies as parameters

### hidden_dependencies
- **Smell**: Function reads from global/env without declaring
- **Example**: `process()` reads `ENV["MODE"]` internally
- **Fix**: Accept mode as parameter: `process(mode)`
