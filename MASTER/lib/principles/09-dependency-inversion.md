# Dependency Inversion (SOLID D)

> Depend on abstractions, not concretions.

tier: solid
priority: 9
auto_fixable: false

## Anti-patterns (violations)

### tight_coupling
- **Smell**: Class directly instantiates its dependencies
- **Example**: `def initialize; @db = PostgreSQL.new; end`
- **Fix**: Inject dependencies through constructor

### hard_coded_dependencies
- **Smell**: Concrete class names scattered throughout code
- **Example**: `HTTPClient.get(url)` called in 20 places
- **Fix**: Inject abstraction, swap implementations easily
