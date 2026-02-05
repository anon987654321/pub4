# Single Responsibility (SOLID S)

> A module should have one, and only one, reason to change.

tier: solid
priority: 5
auto_fixable: true

## Anti-patterns (violations)

### god_class
- **Smell**: Class over 300 lines or 10+ public methods
- **Example**: `ApplicationController` with 50 methods
- **Fix**: Extract concerns into focused classes

### feature_envy
- **Smell**: Method uses another class more than its own
- **Example**: `order.customer.address.city.upcase`
- **Fix**: Move method to the class it envies

### long_method
- **Smell**: Method over 20 lines or 5 nesting levels
- **Example**: 100-line `process_order` with 8 if/else branches
- **Fix**: Extract into smaller named methods
