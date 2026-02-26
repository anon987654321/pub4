# MASTER2

A constitutional AI coding agent. Forged in Ruby and zsh on OpenBSD.
No framework. No scaffold. 30,000 lines of hand-written Ruby governing
80 axioms, 12 adversarial personas, and a portfolio of Rails 8 mobile-first PWAs.

```
MASTER2 2.0.0 (CONSTITUTIONAL) #1
runtime0: x86_64-openbsd * ruby 3.4 * zsh dev%
host0: vmm(4)/vmd(8) * openbsd.amsterdam
corpus0: 80 axioms * 12 personas
models0: claude-4.5-sonnet * deepseek-v3.1 * deepseek-r1
routing0: Replicate primary, OpenRouter fallback
security0: pledge armed
engine0: react * pre_act * rewoo * reflexion
boot0: 145ms
```

## What it is

MASTER2 is the keeper and builder of: Amber (marketplace), Baibl (encyclopedia),
Blognet (publishing), BSDPorts (package tracker), Brgen (city platform),
Hjerterom (dating), Privcam (private streaming), and more — all Rails 8
mobile-first PWAs deployed on OpenBSD with pf, httpd, and relayd.

Every intent flows through a pipeline that earns the right to touch code:

```
intake → guard → route → pressure → execute → lint → render
```

80 axioms enforce at every stage. The council debates before merging.
Beautiful code gets scored. The system runs its own constitution on itself.

## Axioms

Ranked, immutable governance loaded from `data/axioms.yml`.

| Priority | Axiom | Meaning |
|---|---|---|
| 10 | `ABSOLUTE_SAFETY` | Never destroy, never expose secrets |
| 9 | `DRY` | One source of truth |
| 9 | `INVERTED_PYRAMID` | Most important first, everywhere |
| 9 | `STRUNK_WHITE` | Omit needless words |
| 9 | `ZEN_METHOD` | One thing, perfectly, ≤ 7 lines |
| 8 | `KISS` | Simpler is better |
| 8 | `ZSH_NATIVE` | Pure zsh — no bash, sed, awk, tr |
| 7 | `AESTHETIC_VIRTUE` | Exalt the excellent |

Cascade: ABSOLUTE → PROTECTED → ADJUSTABLE. Nothing overrides an ABSOLUTE axiom.

## Architecture

```
bin/master              CLI + REPL entry point
└── Pipeline            intake * guard * executor * lint * render
    ├── Executor        ReAct * PreAct * ReWOO * Reflexion
    ├── Enforcer        14 layer checks + beauty scoring
    ├── Chamber         12-persona adversarial council
    ├── LLM             Replicate primary, OpenRouter fallback
    ├── Speech          Piper TTS + Edge + Replicate, FFmpeg effects
    ├── Server          Web UI via Falcon — canvas orb, SSE, TTS
    └── ProjectMemory   .master/context.yml across sessions

data/
├── axioms.yml          80 axioms — the constitution
├── council.yml         12 personas, 3 veto holders
├── models.yml          model registry with fallback chains
├── personas.yml        8 persona definitions
├── system_prompt.yml   identity, behavior, safety rules
├── exemplars.yml       beautiful patterns cited in prompts
└── 22 more .yml files  platform, typography, quality, detection
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

```
hello                 talk naturally
scan [path]           enforce axioms
reflow <path>         reorder by importance (inverted pyramid)
refactor [path]       LLM-guided multi-pass refactor
self                  run MASTER2 on itself
chamber <text>        12-persona echo chamber debate
model <name>          switch model
models                list available models
goal <text>           set project goal (persists across sessions)
remember <text>       store a decision in project memory
context               show goal and recent decisions
status                constitutional alignment dashboard
budget                cost summary
help                  full command list
```

## Graceful degradation

Never errors out. Primary model fails, it cascades:

```
claude-4.5-sonnet (Replicate)
  → deepseek-r1:free (OpenRouter)
  → gemini-flash:free
  → llama-3.1-8b:free
```

## Web UI

Canvas-based neural orb visualization with 50 geometric states.
Voice-first: TTS greeting, continuous mic listening, orb reacts to audio.
Pitch black. Minimal. The orb contracts and pulses red while thinking.

```
web0: http://localhost:36413/?token=...
```

## Platform

Primary: OpenBSD 7.8 · vmm(4)/vmd(8) · pledge(2) · pf(4)
Runtime: Ruby 3.4 · zsh · no bash, sed, awk, tr
Also runs on: Linux · macOS

## Design

- Unix: one tool, one job, composable
- Inverted pyramid: public first, helpers last
- Strunk & White: omit needless words
- Graceful degradation: never raise to the user
- Self-referential: MASTER2 runs its own rules on itself
