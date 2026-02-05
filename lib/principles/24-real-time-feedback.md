# Real-Time Feedback

> Keep users informed of system status.

tier: ux
priority: 24
auto_fixable: true

## Anti-patterns (violations)

### silent_operations
- **Smell**: No indication work is happening
- **Example**: Click button, nothing for 10 seconds
- **Fix**: Spinner, progress bar, status message

### missing_progress
- **Smell**: Long operation with no updates
- **Example**: "Installing..." for 5 minutes, no detail
- **Fix**: Show step: "Installing 3/7: database..."
