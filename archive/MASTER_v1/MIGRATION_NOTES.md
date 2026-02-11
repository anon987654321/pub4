# MASTER v2 Migration Notes

## New System (v2.0)
Entry point: `bin/start` (Ruby REPL)
Architecture: Unix pipelines with JSON protocol

### New Files Created
**Core Libraries (lib/):**
- db.rb - SQLite database layer
- json_protocol.rb - stdin/stdout JSON protocol
- llm_client.rb - Thin RubyLLM wrapper (24 lines)
- strunk.rb - Text compression
- metz.rb - Quality rules
- typography.rb - Typography formatting
- pledge.rb - OpenBSD sandboxing
- hooks.rb - Event system

**Pipeline Executables (bin/):**
- start - Interactive REPL
- intake, guard, route, ask, critique, chamber
- execute, evolve, quality, converge
- remember, plan, render, seed

**Tests:**
- test/test_protocol.rb
- test/test_db.rb
- test/test_pipeline.rb

**Documentation:**
- README.md (updated)
- CHANGELOG.md (updated with v2.0)
- .zshrc (updated for environment only)

## Old System (v1.x)
Entry point: `bin/cli`
Architecture: Monolithic CLI class

### Old Files (KEEP for backward compatibility)
These files support the existing v1.x system and should NOT be deleted yet:
- lib/cli.rb (3135 lines) - The old monolithic class
- lib/loader.rb - Autoloader for old system
- lib/llm.rb - Old LLM client
- lib/executor.rb - Old code executor
- lib/evolve.rb - Old evolution logic
- bin/cli - Old entry point
- bin/bot - Bot launcher
- bin/validate_principles - Principle validation tool

## Coexistence
Both systems can coexist:
- Old system: `bin/cli` (backward compatible)
- New system: `bin/start` (v2.0 pipeline toolkit)

## Migration Strategy
1. ✅ Phase 1-5: Create new v2.0 files (COMPLETE)
2. ⏸️ Phase 6: Keep old files for now (DO NOT DELETE)
3. 🔄 Future: After v2.0 is validated in production:
   - Deprecate old CLI
   - Remove lib/cli.rb
   - Remove other v1.x files
   - Make bin/start the default

## Testing Both Systems
**v1.x (old):**
```bash
bin/cli ask "What is SOLID?"
```

**v2.0 (new):**
```bash
bin/start  # Interactive REPL
# OR
m-ask What is SOLID?  # Pipeline
```
