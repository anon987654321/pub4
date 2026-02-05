# Liskov Substitution (SOLID L)

> Subtypes must be substitutable for their base types.

tier: solid
priority: 7
auto_fixable: false

## Anti-patterns (violations)

### refused_bequest
- **Smell**: Subclass doesn't use inherited methods
- **Example**: `Square < Rectangle` that ignores `height=`
- **Fix**: Use composition, or don't inherit

### type_checking
- **Smell**: Checking class type instead of using polymorphism
- **Example**: `if obj.is_a?(Dog) then bark else meow`
- **Fix**: Define common interface, let each type implement
