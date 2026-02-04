# MASTER v50.1

Constitutional AI code quality enforcer. Principles as files.

## Quick Start

```bash
cd MASTER
chmod +x bin/cli bin/serve
export OPENROUTER_API_KEY=your_key
./bin/cli
```

## Structure

```
MASTER/
├── bin/
│   ├── cli                   # REPL entry point
│   └── serve                 # HTTP API server
├── lib/
│   ├── master.rb             # Loader
│   ├── result.rb             # Ok/Err monad
│   ├── principle.rb          # Principle parser
│   ├── sandbox.rb            # OpenBSD pledge/unveil
│   ├── boot.rb               # Dmesg-style boot
│   ├── llm.rb                # OpenRouter client (4 tiers)
│   ├── engine.rb             # Scan/detect
│   ├── memory.rb             # Session memory compression
│   ├── server.rb             # Falcon/WEBrick HTTP API
│   ├── cli.rb                # REPL
│   └── principles/           # 32 principles + meta
├── var/
│   └── sessions/             # Session memory storage
├── Gemfile
├── Makefile
└── README.md
```

## Commands

```
help, ?          Show help
principles, p    List loaded principles
scan, s <file>   Scan file for issues
ask, a <prompt>  Send prompt to LLM
serve            Start HTTP API server
compress         Compress session memory
cd <dir>         Change directory
ls [dir]         List directory
pwd              Print working directory
version, v       Show version
quit, q          Exit
<anything else>  Chat with LLM
```

## HTTP API

Start server: `./bin/serve` or from CLI: `serve`

```
GET  /              → { name, version, status }
GET  /health        → { status, principles }
GET  /principles    → { principles: [...] }
POST /scan          → { path: "file.rb" } → issues
POST /ask           → { prompt: "...", tier: "fast" } → response
```

## Session Memory

MASTER remembers across sessions:
- Records all interactions
- Compresses with LLM at session end
- Injects context into next session

```bash
# Compress current session
compress

# Sessions stored in var/sessions/
```

## Principles (Fame Order)

1. **KISS** - Keep It Simple, Stupid
2. **DRY** - Don't Repeat Yourself
3. **YAGNI** - You Aren't Gonna Need It
4. **Separation of Concerns**
5-9. **SOLID** - S, O, L, I, D
10. **Law of Demeter**
11. **Composition Over Inheritance**
12. **Fail Fast**
13. **Principle of Least Astonishment**
14. **Command-Query Separation**
15. **Boy Scout Rule**
16. **Unix Philosophy**
17. **Functional Core, Imperative Shell**
18. **Idempotent Operations**
19. **Defensive Programming**
20. **Graceful Degradation**
21. **Explicit Over Implicit**
22. **Convention Over Configuration**
23. **Progressive Disclosure**
24. **Real-Time Feedback**
25. **Meaningful Names**
26. **Small Functions**
27. **Few Arguments**
28. **No Side Effects**
29. **Immutability**
30. **Pure Functions**
31. **Cost Transparency** (LLM-specific)
32. **Cache Aggressively** (LLM-specific)

## LLM Tiers

- **fast**: gemini-2.0-flash (cheap, quick)
- **code**: grok-3-mini-beta (code-focused)
- **medium**: claude-sonnet-4 (balanced)
- **strong**: claude-opus-4 (highest quality)

## OpenBSD

On OpenBSD, sandbox.rb uses pledge/unveil via Fiddle for security.

## License

MIT
