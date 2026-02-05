# MASTER Typography & UI Spec

Design invariants for terminal output. Typography succeeds when it disappears.

## Color Semantics (Fixed)

```
RESET   \e[0m       # Clear formatting
BOLD    \e[1m       # Primary emphasis
DIM     \e[2m       # Secondary/metadata
RED     \e[31m      # Error only
GREEN   \e[32m      # Success only
YELLOW  \e[33m      # Warning only
CYAN    \e[36m      # Accent (sparingly)
```

One color per meaning. Never reuse.

## Icon Vocabulary (5 max)

```
✓  Success
✗  Error
!  Warning
·  Neutral item
→  Flow/reference
```

Never mix metaphors. No emoji in core output.

## Hierarchy Rules

1. **Primary**: Bold, full brightness
2. **Secondary**: Normal weight, dimmed
3. **Tertiary**: Dim, minimal

Hierarchy via contrast, not decoration. No ASCII art (---, ===, boxes).

## Structure Rules

1. **Whitespace is layout** - Indentation and spacing, not lines
2. **Proximity beats borders** - Group by closeness
3. **Vertical scan first** - Labels left, values aligned right
4. **One concept per screen** - Don't mix status/explanation/instructions

## Output Patterns

### Success (Whisper)
```
✓ Committed 3 files
```

### Error (Speak Loudly)
```
✗ Failed to connect
  Could not reach api.openrouter.ai
  Check OPENROUTER_API_KEY is set
```

### Progressive Summary
```
Result
  Why
    Details
```

### Scannable Alignment
```
Status     ✓ Active
Commits      1,247
Cost        $0.04
```

### State Transitions
```
Analyzing...
✓ Complete (3 issues found)
```

## Anti-Patterns

- ASCII separators (━━━, ═══, ---)
- Boxes and frames (╭╮╰╯)
- Mixed icon styles (✓ + ✔ + OK)
- Color without meaning
- Verbose success messages
- Motion for static info
- Surprise output reordering

## Verbosity Levels

- **Silent**: Only errors
- **Normal**: Result + summary (default)
- **Verbose**: Full trace (--verbose)

Successful operations whisper. Errors speak loudly.
