# MASTER v2.0 - Breaking Changes

## Overview
MASTER v2.0 is a complete architectural transformation from monolithic CLI to Unix pipeline toolkit. This is a **breaking change** that removes the old CLI system.

## What's Removed
- ❌ `lib/cli.rb` (3135 lines) - Monolithic CLI class
- ❌ Old `bin/cli` entry point (now obsolete)

## What Breaks
The following components depended on the old CLI and will no longer work:
- `bin/cli` - Old entry point (use `bin/start` instead)
- `lib/bot_manager.rb` - Referenced CLI constants
- `lib/cli_v226.rb` - Alternative CLI (superseded)
- Tests that use `require_relative '../lib/loader'`:
  - test/test_cli_traces.rb
  - test/test_cli_context.rb
  - test/test_master.rb
  - test/test_enhancements.rb
  - test/test_bot_integration.rb
  - test/test_unified_v226.rb

## Migration Path

### Old Way (v1.x)
```bash
bin/cli ask "What is SOLID?"
bin/cli refactor code.rb
bin/cli evolve
```

### New Way (v2.0)
```bash
# Interactive REPL
bin/start

# Pipeline
echo '{"text":"What is SOLID?"}' | \
  bin/intake | bin/guard | bin/route | bin/ask | bin/render

# Shell alias
m-ask What is SOLID?

# Self-modification
echo '{"file":"lib/code.rb"}' | bin/evolve
```

## Old Tests
Old tests that depended on `lib/cli.rb` will need to be rewritten for the new architecture or removed:
- test_cli_traces.rb → test_pipeline.rb (DONE)
- test_cli_context.rb → (removed - context now in JSON)
- test_master.rb → test_db.rb (DONE)
- test_bot_integration.rb → (removed - bots not in scope for v2.0)

## What Still Works
- ✅ Data files (principles.yml, personas.yml)
- ✅ Configuration in data/
- ✅ Documentation
- ✅ The v2.0 pipeline system (fully functional)

## Rationale
The monolithic 3135-line cli.rb violated multiple principles:
- Single Responsibility Principle (SRP)
- Don't Repeat Yourself (DRY)
- KISS (Keep It Simple)

The new pipeline architecture:
- Each executable under 200 lines
- Each library under 300 lines
- Composable via Unix pipes
- Testable in isolation
- Follows Unix philosophy

## Rollback (if needed)
If you need the old system temporarily:
```bash
git checkout HEAD~1 -- MASTER/lib/cli.rb
```

But be aware: v2.0 is the future. The old system is deprecated.
