# Open-Closed (SOLID O)

> Open for extension, closed for modification.

tier: solid
priority: 6
auto_fixable: false

## Anti-patterns (violations)

### shotgun_surgery
- **Smell**: One change requires edits in many files
- **Example**: Adding payment type requires 12 file changes
- **Fix**: Use strategy pattern, dependency injection

### rigid_design
- **Smell**: Can't extend without modifying core code
- **Example**: Giant switch statement for each type
- **Fix**: Use polymorphism, plugins, or hooks
