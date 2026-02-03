# Constitutional AI v47

LLM-native code quality enforcement with auto-bootstrap and sensible defaults.

## Quick Start

```bash
# Just run it - gems auto-install on first use
ruby cli.rb your_file.rb

# Optional: Set API key for full LLM reasoning
export OPENROUTER_API_KEY="your-key"
```

## Features

- **Auto-Bootstrap**: Missing gems install automatically (OpenBSD doas, Termux pkg supported)
- **32 Principles**: From SOLID to Unix Philosophy
- **7-Phase Workflow**: Discover → Analyze → Ideate → Design → Implement → Validate → Deliver
- **LLM-Native Detection**: Zero regex patterns, pure reasoning
- **Auto-Iteration**: Converges to 100/100 score automatically
- **Battle-Tested Safety**: 15 edge cases handled (cost limits, file locking, rollback, binary detection, etc.)
- **Multi-Model RAG**: Fallback cascade (Claude → GPT-4 → Gemini)
- **Cross-Platform**: Windows, macOS, Linux, OpenBSD, Termux

## Architecture

**Functional Core + Imperative Shell**

- **Core** (`Core::*`): Pure functions (PrincipleRegistry, LLMDetector, ScoreCalculator)
- **Shell** (Classes): IO, state, LLM calls (Constitution, LLMClient, AutoEngine)

## Web Interface

Open `cli.html` for interactive AI orb with:
- Voice recognition
- Audio-reactive visuals
- Tunnel/starfield rendering
- Multi-persona TTS

## Safety Features

- File locking (concurrent-safe)
- Transactional rollback
- Cost protection ($1/file, $10/session)
- Binary file detection
- Convergence detection
- Priority-aware fixes

## Configuration

All rules in `master.yml`:
- Modify principles
- Adjust LLM settings
- Tune safety limits
- Add language support

## Examples

```bash
# Self-validate
ruby cli.rb cli.rb

# Show cost
ruby cli.rb --cost

# Rollback changes
ruby cli.rb app.rb --rollback
```

## Principles Hierarchy

1. **Axioms** (Priority 10): Clarity, Simplicity, Explicit > Implicit
2. **SOLID** (Priority 7-8): SRP, OCP, LSP, ISP, DIP
3. **Clean Code** (Priority 6-7): Names, Small Functions, CQS
4. **Operations** (Priority 9): Idempotent, Safe Refactoring

## CLI Options

```
ruby cli.rb <file>           # Auto-process file
ruby cli.rb --help           # Show help
ruby cli.rb --version        # Show version
ruby cli.rb --cost           # Show LLM usage stats
ruby cli.rb --rollback <f>   # Restore from backup
```

## Environment Variables

```bash
OPENROUTER_API_KEY   # Required for AI features
VERBOSE=1            # Show detailed logs
```

## Auto-Processing Flow

1. **Language Detection**: Asks user or detects from content
2. **Iteration Loop**: Scans → Fixes → Rescans until 100/100
3. **AI Refactoring**: Auto-fixes remaining violations
4. **Validation**: 7-phase quality gates
5. **Backup**: Creates rollback point automatically

## Safety Guarantees

- ✅ **Atomic operations**: All-or-nothing file updates
- ✅ **Concurrent-safe**: File locking with stale detection
- ✅ **Cost-bounded**: Hard limits per file and session
- ✅ **Memory-bounded**: Chunking for large files
- ✅ **Convergence detection**: Stops infinite loops
- ✅ **Priority-aware**: Won't introduce worse violations
- ✅ **Rollback-ready**: 5 backups kept automatically

## Core Principles

### Axioms (Priority 10)

1. **Clarity Over Cleverness**: Written for reader, understandable at 3am
2. **KISS**: Simplest solution that works
3. **Explicit Over Implicit**: No hidden magic, behavior visible

### SOLID (Priority 7-8)

11. **Single Responsibility**: One reason to change
12. **Open/Closed**: Open for extension, closed for modification
13. **Liskov Substitution**: Subtypes substitutable for base
14. **Interface Segregation**: Many specific interfaces over one general
15. **Dependency Inversion**: Depend on abstractions, not concretions

### Clean Code (Priority 6-7)

19. **Meaningful Names**: Intention-revealing, pronounceable, searchable
20. **Small Functions**: Do one thing, max 10 lines
21. **Few Arguments**: Ideal 0, next 1, avoid 2, justify 3, never 4+
22. **Command-Query Separation**: Change state OR return data, never both

### Operations (Priority 9)

29. **Idempotent Operations**: Running twice produces same result as once
32. **Safe Refactoring with Rollback**: Always backup before modification

## LLM Configuration

### Detection

- **Primary**: anthropic/claude-3.5-sonnet
- **Fallbacks**: openai/gpt-4o, google/gemini-2.0-flash-exp:free
- **Prompt**: Analyzes against all 32 principles
- **Output**: JSON array of violations with line numbers, severity, fix suggestions

### Refactoring

- **Strategies**: extract_method, rename_variable, extract_class, flatten_nesting, simplify_condition
- **Temperature**: 0.1-0.3 (deterministic)
- **Max Tokens**: 500-5000 depending on strategy

### Cost Tracking

```
tokens=1234 cached=890 cost=$0.0045
```

Every LLM call shows:
- Total tokens used
- Cached tokens (90% cost reduction)
- Estimated cost in USD

## File Safety

Validates before processing:
- ✅ Regular file (not symlink, socket, device)
- ✅ Read/write permissions
- ✅ Not binary (checks null bytes, extensions)
- ✅ Size under 10MB
- ✅ UTF-8 encodable

## Convergence Detection

Stops iteration if:
- ✅ Zero violations (success)
- ⚠️ Loop detected (same violations 3x)
- ⚠️ Oscillation detected (alternating states)
- ⚠️ No improvement (3 iterations without progress)
- ❌ Max iterations reached (default: 10)
- ❌ Total violations exceeds limit (10,000)

## Language Support

Currently supported:
- Ruby (.rb, .rake, .gemspec)
- Python (.py)
- JavaScript (.js, .jsx, .ts, .tsx)
- Markdown (.md, .markdown)
- YAML (.yml, .yaml)
- Shell (.sh, .bash, .zsh)

**Extensible**: Add to `master.yml` → `language_detection` → `supported`

## Conflict Resolution

When principles conflict:
- **Strategy**: Highest priority wins
- **Special Rules**: 
  - DRY vs WET/AHA: Favor WET if <3 duplications
  - Clarity vs Simplicity: Favor clarity (both priority 10, clarity is axiom)
  - Fix introduces higher priority violation: Reject fix

## Backups

Location: `.constitutional_backups/`

```bash
# List backups
ls .constitutional_backups/

# Manual restore (keeps 5 most recent)
ruby cli.rb --rollback app.rb
```

## Status

**Version**: 46.1  
**Date**: 2026-02-03  
**Status**: Production-ready  
**Philosophy**: Constitutional correctness through LLM reasoning, battle-tested safety

## Dependencies

### Required
- Ruby 3.0+
- ruby_llm gem (for LLM features)

### Optional
- tty-spinner gem (for better UX)

### Graceful Degradation
- Works without `ruby_llm` (manual mode)
- Works without `tty-spinner` (text fallback)
- Works without API key (analysis-only mode)

## Development

```bash
# Self-validate the CLI
ruby cli.rb cli.rb

# Self-validate the constitution
ruby cli.rb master.yml

# Run with verbose logging
VERBOSE=1 ruby cli.rb app.rb
```

## Web Interface

`cli.html` provides a visual AI companion:

- **Voice Input**: Click orb to speak
- **Text Input**: Type in top-left header
- **Visual Feedback**: Audio-reactive animations
- **States**: Idle (breathing) → Listening (pulsing) → Thinking (spinner) → Speaking (animated)
- **Personas**: 15 voice profiles (from deep dragon to anxious guru)

### Features

- WebGL tunnel/starfield rendering
- Astral particle system (40 particles)
- Dimensional effects (sacred geometry, DMT-inspired)
- Audio visualization (FFT analysis)
- Organic behaviors (wandering, startle, tentacles)
- Real-time lighting (specular, rim, shadow)

### Integration

```javascript
// Connect to backend (optional)
POST /chat { message: "..." }
GET /poll  // Long-polling for server TTS

// Or standalone with browser TTS
Ares.speak("Hello world")
```

## Philosophy

> Code read 10x more than written.
> Quality constitutional, not negotiable.
> LLM reasoning replaces brittle regex patterns.

### Design Decisions

1. **LLM-Native**: No regex patterns. Single LLM call replaces 50+ rules.
2. **Flat Registry**: Principles referenced by ID. No duplication.
3. **Sensible Defaults**: One command does everything.
4. **Safety First**: 15 edge cases handled (cost, concurrency, convergence, etc.)
5. **Functional Core**: Pure functions, testable without mocks.
6. **Graceful Degradation**: Works offline, without API key, without gems.

## Refinements (from v1 to v46)

- ✅ Pattern detection: 50+ regex → Single LLM reasoning
- ✅ Section duplication: Same rule in 3 places → Flat registry
- ✅ User workflow: 3+ commands → Single command
- ✅ Edge cases: Basic errors → 15 production scenarios
- ✅ Language detection: Extension-only → Ask user + content analysis
- ✅ LLM fallback: Single model → Multi-model RAG
- ✅ Cost tracking: Per-call → Per-file + per-session limits
- ✅ Convergence: Fixed iterations → Loop/oscillation detection
- ✅ Fix validation: Blind apply → Priority-aware rejection
- ✅ File safety: Assume regular → Check binary/permissions/special
- ✅ Concurrency: No locking → File locking with stale detection
- ✅ Transactions: Partial updates → Atomic with rollback
- ✅ Memory: Unlimited → Bounded history + GC
- ✅ YAML safety: Unrestricted → Size/timeout/bomb detection
- ✅ Priority system: None → 10-point scale with conflict resolution
- ✅ Separation: Mixed logic → master.yml (rules) + cli.rb (enforcer)

## Examples

### Basic Usage

```bash
# Analyze and fix a file
ruby cli.rb app/models/user.rb

# Output:
# Constitutional AI 46.1
# ...
# constitutional: ready
#
# [09:15:32] PHASE  Auto-processing app/models/user.rb (ruby)
# [09:15:33] INFO   Iteration 1: 8 violations
# [09:15:35] INFO   Iteration 2: 3 violations
# [09:15:36] INFO   Iteration 3: 0 violations
# [09:15:36] OK     ✓ Zero violations after 3 iteration(s)
# [09:15:36] OK     ✓ Score 100/100 - Zero violations
```

### With Verbose Logging

```bash
VERBOSE=1 ruby cli.rb app.rb

# Shows:
# - LLM model selection
# - Token usage per call
# - Cost breakdown
# - Convergence analysis
# - Memory GC triggers
```

### Cost Monitoring

```bash
# Check cumulative cost
ruby cli.rb --cost

# Output:
# LLM Usage:
#   Calls:  47
#   Tokens: 23,441
#   Cost:   $0.2156
```

### Rollback

```bash
# Process file
ruby cli.rb app.rb

# Undo changes
ruby cli.rb --rollback app.rb

# List available backups
ls .constitutional_backups/app.rb.*.backup
```

## Contributing

1. Add principle to `master.yml`
2. Self-validate: `ruby cli.rb cli.rb`
3. Test on corpus: `find . -name "*.rb" -exec ruby cli.rb {} \;`

## License

See repository for license details.

## Credits

- **Philosophy**: Inspired by Constitutional AI (Anthropic)
- **Architecture**: Functional Core, Imperative Shell (Gary Bernhardt)
- **Principles**: SOLID, Clean Code, Unix Philosophy, Gall's Law
- **Ecosystem Intelligence**: Clawdbot/Moltbot/OpenClaw analysis (3,248 repos)

## Status Indicators

✅ Complete and production-ready  
⚠️ Functional but needs improvement  
❌ Missing or broken

---

**Version**: 46.1  
**Last Updated**: 2026-02-03  
**Repository**: anon987654321/pub4