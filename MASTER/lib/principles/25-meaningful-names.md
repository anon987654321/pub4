# Meaningful Names

> Names reveal intent. Clean Code principle.

tier: clarity
priority: 25
auto_fixable: true

## Anti-patterns (violations)

### cryptic_names
- **Smell**: Single letter or unclear abbreviations
- **Example**: `def p(x, y, z)` - what do these mean?
- **Fix**: `def process_payment(amount, currency, user)`

### abbreviated_names
- **Smell**: Shortened names that obscure meaning
- **Example**: `usrAcctMgr` instead of `user_account_manager`
- **Fix**: Spell it out, IDE has autocomplete

### generic_names
- **Smell**: Names that could mean anything
- **Example**: `data`, `info`, `temp`, `handler`
- **Fix**: Be specific: `user_profile`, `error_message`
