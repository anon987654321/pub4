# KISS (Keep It Simple, Stupid)

> The most famous principle. Complexity is the enemy. Simple solutions are easier to understand, debug, and maintain.

tier: core
priority: 1
auto_fixable: false

## Anti-patterns (violations)

### over_engineering
- **Smell**: Building for hypothetical future requirements
- **Example**: Abstract factory for a single implementation
- **Fix**: Delete abstractions until it hurts

### unnecessary_complexity
- **Smell**: Nested conditionals, convoluted logic, too many parameters
- **Example**: 5-level deep if/else chains
- **Fix**: Extract methods, use early returns, simplify

### premature_abstraction
- **Smell**: Creating interfaces/base classes before second use case
- **Example**: `IUserRepository` with only `UserRepository`
- **Fix**: Wait for duplication, then abstract
