---
name: OpenCrabs (Rust MASTER cousin)
description: github.com/adolfousier/opencrabs — Rust/Ratatui TUI agent, philosophical cousin of MASTER. Solo author, 5 stars, MIT. Worth-stealing patterns listed.
type: reference
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
**Repo:** github.com/adolfousier/opencrabs · docs.opencrabs.com · 34 MB binary, 57 MB RSS, latest v0.2.15 (Feb 2026), Cargo nightly required (2024 edition + `portable_simd`).

**Architecture:** TUI/CLI → Brain → Services → SQLx/SQLite → LLM providers. Layered Rust + Tokio + Ratatui. Linux/macOS/Windows; no OpenBSD support, no `pledge`/`unveil`.

**Patterns worth stealing for MASTER:**
1. **Brain-files re-read every turn.** System prompt assembled per turn from workspace MD files (SOUL/IDENTITY/USER/AGENTS/TOOLS/MEMORY/SECURITY/BOOT/HEARTBEAT). Edit between turns → effect immediate, no rebuild. Same shape as MASTER's `data/*.yml`.
2. **FTS5 BM25 memory search via existing SQLite.** Zero new deps, ~0.4ms/query. Ruby equivalent: `sqlite3` gem + FTS5 — free.
3. **Inline compaction summary.** When auto-compaction fires at 70% ctx, summary written to chat AND daily log so user sees what was kept. Transparency over magic.
4. **`/rebuild` + Unix `exec()` hot-restart.** Self-edit → `cargo build --release` async → `ProgressEvent::RestartReady` → `exec()` swap → resume session via SQLite. No context loss.
5. **Sub-agent tool exclusion list.** `spawn_agent`/`rebuild`/`evolve` ALWAYS_EXCLUDED from sub-agents — prevents recursive self-mod.

**Risks visible in their changelog (don't blindly copy):** RSI runs without human approval (writes to `~/.opencrabs/rsi/improvements.md`); README admits agent hallucinates tool calls in corrupted sessions ("fix coming"). Bus factor 1, pre-traction.

**Don't conflate:** `mo-vic/OpenCrab` (singular, fine-tuning distillation, unrelated) and the empty `opencrab` org are different projects.
