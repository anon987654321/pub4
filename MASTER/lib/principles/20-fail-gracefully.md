# Graceful Degradation

> Partial functionality beats total failure.

tier: reliability
priority: 20
auto_fixable: false

## Anti-patterns (violations)

### missing_fallback
- **Smell**: Single point of failure crashes everything
- **Example**: Cache miss = entire page 500 error
- **Fix**: Fallback to database, show stale data

### cascade_failures
- **Smell**: One service down takes others with it
- **Example**: Auth service down = all services dead
- **Fix**: Circuit breakers, timeouts, bulkheads
