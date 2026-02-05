# Small Functions

> Functions should do one thing, do it well.

tier: clean_code
priority: 26
auto_fixable: true

## Anti-patterns (violations)

### long_method
- **Smell**: Method over 20 lines
- **Example**: 150-line `process_order()` method
- **Fix**: Extract: `validate()`, `calculate()`, `persist()`

### multiple_responsibilities
- **Smell**: Method does unrelated things
- **Example**: `save_and_email_and_log()`
- **Fix**: Split into `save()`, `email()`, `log()`
