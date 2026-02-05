# Immutability

> Prefer immutable data. Fewer bugs, easier reasoning.

tier: functional
priority: 29
auto_fixable: false

## Anti-patterns (violations)

### mutable_shared_state
- **Smell**: Multiple threads/functions modify same object
- **Example**: Global config hash modified at runtime
- **Fix**: Freeze objects, use thread-local copies

### defensive_copies_needed
- **Smell**: Must copy data to prevent corruption
- **Example**: `arr.dup` everywhere to avoid mutation
- **Fix**: Use frozen/immutable data structures by default
