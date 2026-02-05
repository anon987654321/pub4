# Interface Segregation (SOLID I)

> Clients should not depend on interfaces they don't use.

tier: solid
priority: 8
auto_fixable: false

## Anti-patterns (violations)

### fat_interface
- **Smell**: Interface with too many methods
- **Example**: `IRepository` with 30 methods, most unused
- **Fix**: Split into smaller role-based interfaces

### forced_implementation
- **Smell**: Empty or stub implementations of interface methods
- **Example**: `def unused_method; raise NotImplementedError; end`
- **Fix**: Remove method from interface, use mixins
