# Boy Scout Rule

> Leave the code cleaner than you found it.

tier: practice
priority: 15
auto_fixable: true

## Anti-patterns (violations)

### technical_debt_ignored
- **Smell**: TODO comments never addressed
- **Example**: `# FIXME: this is broken` from 2019
- **Fix**: Fix it now or delete the comment

### broken_windows
- **Smell**: Visible code rot left unfixed
- **Example**: Dead imports, unused variables, lint warnings
- **Fix**: Clean up on each commit, no exceptions
