# Convention Over Configuration

> Sensible defaults reduce boilerplate. Rails fame.

tier: productivity
priority: 22
auto_fixable: false

## Anti-patterns (violations)

### excessive_configuration
- **Smell**: Require config for every behavior
- **Example**: 200-line XML to configure ORM
- **Fix**: Provide sensible defaults, override only when needed

### missing_defaults
- **Smell**: No default behavior, everything explicit
- **Example**: `connect(host, port, timeout, retry, ...)` all required
- **Fix**: Default to localhost:5432, timeout 30s, etc.
