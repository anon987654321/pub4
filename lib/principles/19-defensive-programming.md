# Defensive Programming

> Never trust input. Validate at boundaries.

tier: reliability
priority: 19
auto_fixable: true

## Anti-patterns (violations)

### missing_validation
- **Smell**: User input used without checks
- **Example**: `File.read(params[:path])` - path traversal
- **Fix**: Whitelist, sanitize, validate all input

### trust_boundary_violation
- **Smell**: Internal code trusts external data
- **Example**: API response parsed without schema validation
- **Fix**: Validate at boundaries, fail on invalid data
