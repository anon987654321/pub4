# MASTER2

Constitutional AI coding agent. Ruby + zsh on OpenBSD.
No framework. No scaffold. 30,000 lines governing 80 axioms,
12 adversarial personas, and a portfolio of Rails 8 PWAs.

```
MASTER2 2.0.0 (CONSTITUTIONAL) #1
runtime0: x86_64-openbsd * ruby 3.4 * zsh dev%
host0: vmm(4)/vmd(8) * openbsd.amsterdam
corpus0: 80 axioms * 12 personas
models0: gpt-5.2 * claude-4-sonnet * gemini-3.1-pro
routing0: Replicate primary → free OpenRouter fallback
security0: pledge armed
engine0: react * pre_act * rewoo * reflexion
boot0: 145ms
```

## What it is

MASTER2 keeps and builds: Amber (marketplace), Baibl (encyclopedia),
Blognet (publishing), BSDPorts (package tracker), Brgen (city platform),
Hjerterom (dating), Privcam (streaming) — Rails 8 PWAs on OpenBSD.

Every intent flows through a pipeline that earns the right to touch code:

```
intake → guard → route → execute → lint → render
```

80 axioms enforce at every stage. Council debates before merging.
The system runs its own constitution on itself. Beautiful code gets scored.

## Axioms

| Priority | Axiom | Meaning |
|---|---|---|
| 10 | `ABSOLUTE_SAFETY` | Never destroy, never expose secrets |
| 9 | `DRY` | One source of truth |
| 9 | `INVERTED_PYRAMID` | Most important first, everywhere |
| 9 | `STRUNK_WHITE` | Omit needless words |
| 9 | `ZEN_METHOD` | One thing, perfectly, ≤ 7 lines |
| 8 | `KISS` | Simpler is better |
| 8 | `ZSH_NATIVE` | Pure zsh — no bash, sed, awk |
| 7 | `AESTHETIC_VIRTUE` | Exalt the excellent |

## Architecture

```
bin/master              CLI + REPL
└── Pipeline            guard * executor * lint * render
    ├── Executor        ReAct * PreAct * ReWOO * Reflexion
    ├── Enforcer        axiom checks + beauty scoring
    ├── Chamber         12-persona adversarial council
    ├── LLM             Replicate(0) → free OpenRouter(1) → paid(2)
    ├── Speech          Piper TTS + Edge + Replicate
    ├── Server          Falcon — canvas orb, SSE, /chat, /tts
    └── Session         continuity across models and turns

data/
├── axioms.yml          80 axioms
├── models.yml          tier registry: premium→strong→fast→cheap→free
├── council.yml         12 personas, 3 veto holders
├── system_prompt.yml   identity, behavior, safety
└── 24 more .yml files  platform, language, quality, detection
```

## Install

```zsh
git clone https://github.com/anon987654321/pub4
cd pub4/MASTER2
bundle install
export REPLICATE_API_KEY=r8_...
export OPENROUTER_API_KEY=sk-or-v1-...
bin/master
```

## Commands

Free-form text goes directly to the LLM — no prefix needed.

```
scan [path]           enforce axioms
fix [path]            auto-fix violations
refactor [path]       LLM-guided refactor
chamber <file>        12-persona adversarial review
evolve [path]         self-improvement cycle
model <name>          switch model
models                list available models
health                system health check
status                constitutional alignment
integrations [sync]  OpenClaw/Telegram/local-AI repo pack
help                  full command list
```

## Graceful degradation

```
gpt-5.2 (Replicate)
  → claude-4-sonnet (Replicate)
  → gemini-3.1-pro (Replicate)
  → qwen3-coder:free (OpenRouter)
  → hermes-3-405b:free (OpenRouter)
  → ... 7 more free models
```

Credit exhaustion opens paid circuits only — free models always reachable.

## Web UI

Canvas neural orb, 50 geometric states. Voice-first.
Pitch black. Orb contracts and pulses red while thinking.

```
web0: http://localhost:36413/?token=...
```

## Platform

Primary: OpenBSD 7.8 · vmm(4) · pledge(2) · pf(4)
Runtime: Ruby 3.4 · zsh · no bash, sed, awk, tr
Also: Linux · macOS

## Design

- Unix: one tool, one job, composable
- Inverted pyramid: public first, helpers last
- Strunk & White: omit needless words
- Graceful degradation: never raise to the user
- Self-referential: MASTER2 runs its own rules on itself
