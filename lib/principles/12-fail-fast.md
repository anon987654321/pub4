# Fail Fast

> Errors should be reported as soon as they are detected.

tier: reliability
priority: 12
auto_fixable: true

## Anti-patterns (violations)

### silent_failure
- **Smell**: Errors caught and ignored
- **Example**: `rescue => e; end` (empty rescue)
- **Fix**: Log, re-raise, or handle explicitly

### swallowed_exceptions
- **Smell**: Catching broad exceptions, hiding root cause
- **Example**: `rescue Exception` that returns nil
- **Fix**: Catch specific exceptions, let others bubble

### defensive_nulls
- **Smell**: Returning nil instead of raising on error
- **Example**: `find_user || nil` hiding "not found"
- **Fix**: Raise exception or use Result monad
