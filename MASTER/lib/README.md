# MASTER/lib - Core Pipeline Libraries

This directory contains the **8 core library files** used by the pipeline executables in `bin/`.

## Core Files (Keep)

1. **db.rb** - SQLite connection and queries (single source of truth)
2. **json_protocol.rb** - stdin/stdout JSON protocol (used by all bins)
3. **pledge.rb** - OpenBSD pledge/unveil security wrappers
4. **strunk.rb** - Strunk & White text compression (used by bin/intake)
5. **metz.rb** - Sandi Metz quality rules (used by bin/quality)
6. **typography.rb** - Bringhurst formatting (used by bin/render)
7. **llm_client.rb** - HTTP client for LLM APIs (used by bin/ask, bin/chamber)
8. **hooks.rb** - Hook registry for extensibility

## Directory Structure

```
lib/
├── db.rb               # SQLite connection + queries
├── json_protocol.rb    # stdin/stdout JSON protocol
├── llm_client.rb       # HTTP client for LLM APIs
├── strunk.rb           # Text compression
├── metz.rb             # Quality rules
├── pledge.rb           # OpenBSD security
├── typography.rb       # Formatting
└── hooks.rb            # Hook system
```

## Removed Files

As of 2026-02-06, the following 54+ top-level files were removed:
- cli.rb (94 KB God object) → replaced by bin/start (Zsh REPL)
- chamber.rb → replaced by bin/chamber
- converge.rb → replaced by bin/converge
- council.rb → replaced by bin/chamber
- All other monolithic files

Plus ~70 files in subdirectories (actors/, agents/, cli/, config/, core/, etc.)

**Total reduction:** 132 files → 8 files

## Migration Notes

If you need old functionality:
1. Check the backup at `/archive_lib_20260206/lib/`
2. Port it to the new pipeline architecture
3. Create a new bin/ executable if needed
4. Update lib/ only if it's shared code

## Design Principles

- **KISS**: Each file has one clear purpose
- **DRY**: Shared code only, no duplication
- **Unix Philosophy**: Small, composable, testable
- **SOLID**: Single responsibility for each module
