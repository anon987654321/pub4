# Law of Demeter

> Only talk to your immediate friends. Avoid train wrecks.

tier: design
priority: 10
auto_fixable: true

## Anti-patterns (violations)

### message_chains
- **Smell**: Long chains like `a.b.c.d.e`
- **Example**: `order.customer.address.city.downcase`
- **Fix**: Add delegate method: `order.customer_city`

### inappropriate_intimacy
- **Smell**: Class knows too much about another's internals
- **Example**: Accessing private fields via reflection
- **Fix**: Use public interface, hide implementation

### feature_envy
- **Smell**: Method uses another object's data excessively
- **Example**: Method with 10 calls to `other.field`
- **Fix**: Move method to the class it envies
