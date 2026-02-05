# Idempotent Operations

> Same operation, same result. Critical for distributed systems.

tier: reliability
priority: 18
auto_fixable: false

## Anti-patterns (violations)

### non_idempotent_mutations
- **Smell**: Repeated calls produce different results
- **Example**: `increment_counter()` called twice = +2
- **Fix**: Use `set_counter(value)` instead

### unsafe_retries
- **Smell**: Retry logic without idempotency keys
- **Example**: Payment API retried without dedup
- **Fix**: Add idempotency key, check before processing
