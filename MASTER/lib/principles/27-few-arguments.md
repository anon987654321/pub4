# Few Arguments

> Ideal is zero to two arguments. Three is suspicious.

tier: clean_code
priority: 27
auto_fixable: true

## Anti-patterns (violations)

### long_parameter_list
- **Smell**: More than 4 parameters
- **Example**: `create(a, b, c, d, e, f, g)` - 7 args
- **Fix**: Group into parameter object or builder

### parameter_objects_needed
- **Smell**: Same params passed together repeatedly
- **Example**: `(host, port, user, pass)` in 10 methods
- **Fix**: Create `ConnectionConfig` object
