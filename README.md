# Constitutional AI – The Code Janitor That Roasts You While Fixing Your Sins 🤖💅

Your code is a beautiful disaster.  
We both know it.  
This tool is the brutally honest friend who says "bro… what is this?" and then quietly makes it better.

Think Clippy, but instead of "it looks like you're writing a letter" it's "it looks like you're torturing future developers, let me help."

## Why This Exists

You write code once.  
Your teammates (and future you at 2 a.m.) read it 900 times.  
This little gremlin makes sure it doesn't cause therapy bills.

It:
- Spots confusing names faster than your mom spots a lie
- Breaks 80-line horror methods into bite-sized, non-traumatizing chunks
- Replaces `eval()` with "please don't summon Cthulhu" warnings
- Keeps backups so you can panic-revert like a pro

## Get In, Loser, We're Cleaning Code

```bash
# 1. Got Ruby? No? https://www.ruby-lang.org — 5 minutes, tops.
# 2. Set your API key (one time)
export OPENROUTER_API_KEY="your-key-here"

# 3. Let it rip
ruby cli.rb disaster.rb               # one tragic file
ruby cli.rb .                         # nuke the whole directory (with love)
ruby cli.rb --watch .                 # helicopter parent mode
```

Watch it think out loud in real time — like pair-programming with someone who never sleeps and never judges… out loud.

## Commands That Make You Look Cool

```bash
ruby cli.rb app/models/user.rb        # fix one poor soul
ruby cli.rb lib/                      # whole folder therapy session
ruby cli.rb --json **/*.rb            # CI mode (for the robots)
ruby cli.rb --watch .                 # auto-fix on save
ruby cli.rb --cost                    # see how much you owe the AI overlords
```

## What It Actually Does (Serious Mode)

### v47.5 Features

- **Tiered LLM Pipeline**: Fast (Qwen) → Medium (Sonnet) → Strong (Opus) = 60-80% cost savings
- **Prompt Caching**: System prompts cached 1h = 75-90% savings on Claude
- **Auto-Bootstrap**: Missing gems install automatically (OpenBSD, Termux, Windows all work)
- **32 Principles**: From SOLID to Unix Philosophy
- **7-Phase Workflow**: Discover → Analyze → Ideate → Design → Implement → Validate → Deliver
- **Watch Mode**: Auto-reanalyze on file save
- **Git History Tracking**: Compare scores across commits
- **TreeWalk + FileCleaner**: Show structure, normalize whitespace before analysis

### Safety Features (We're Not Monsters)

- 🔒 File locking (no race conditions)
- ↩️ Transactional rollback (`.constitutional_backups/`)
- 💰 Cost protection ($1/file, $10/session max)
- 🚫 Binary file detection (won't touch your PNGs)
- 🔄 Convergence detection (stops infinite loops)
- ⚖️ Priority-aware fixes (won't make things worse)

## Principles Hierarchy

1. **Axioms** (Priority 10): Clarity, Simplicity, Explicit > Implicit
2. **SOLID** (Priority 7-8): SRP, OCP, LSP, ISP, DIP
3. **Clean Code** (Priority 6-7): Names, Small Functions, CQS
4. **Operations** (Priority 9): Idempotent, Safe Refactoring

## Cross-Platform (We Don't Discriminate)

| Platform | Status |
|----------|--------|
| OpenBSD | ✅ First-class citizen (pledge/unveil ready) |
| Termux | ✅ Android terminal works |
| macOS | ✅ |
| Linux | ✅ |
| Windows/Cygwin | ✅ |

## Architecture (For the Nerds)

**Functional Core + Imperative Shell**

- **Core** (`Core::*`): Pure functions (PrincipleRegistry, LLMDetector, ScoreCalculator)
- **Shell** (Classes): IO, state, LLM calls (Constitution, LLMClient, TieredLLM)
- **Symbiosis**: `cli.rb ⟷ master.yml` - neither functions alone

## Environment Variables

```bash
OPENROUTER_API_KEY   # Required for AI features
VERBOSE=1            # Debug mode (see everything)
```

## Pro Tips

```bash
# Self-validate the validator (very meta)
ruby cli.rb cli.rb master.yml

# Interactive mode
ruby cli.rb
> all                 # process everything
> cost                # show spending
> quit                # peace out
```

---

*End transmission. May your code be clean and your merge conflicts few.* 🙏
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