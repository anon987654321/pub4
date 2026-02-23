# MASTER2

Constitutional AI coding assistant. Every edit is a decision with consequences.

```
MASTER 2.0.0 (CONSTITUTIONAL) #1
runtime0: x86_64-openbsd * ruby 3.4 * zsh dev%
corpus0:  80 axioms * 12 personas
models0:  claude-sonnet-4-6 * deepseek-v3-2 * deepseek-r1
boot0:    52ms * smoke ok

master * main * claude-sonnet-4-6 ❯
```

---

## What it does

Routes your intent through a staged pipeline that narrows uncertainty before
touching code. Each phase earns the right to proceed:

```
intake -> guard -> route -> pressure -> ask/refactor -> lint -> render
```

The constitutional engine runs on every pass. Violations surface. Beautiful
code gets a score (`✦ 12`). The council debates before merging.

---

## Axioms

MASTER2 is governed by a constitution -- a ranked set of axioms loaded from
`data/axioms.yml`. They apply at every level of every run.

| Priority | Axiom | Meaning |
|---|---|---|
| 10 | `ABSOLUTE_SAFETY` | Never destroy; never expose secrets |
| 9 | `DRY` | One source of truth |
| 9 | `INVERTED_PYRAMID` | Most important first, everywhere |
| 9 | `STRUNK_WHITE` | Omit needless words |
| 9 | `ZEN_METHOD` | One thing, perfectly, ≤ 7 lines |
| 8 | `KISS` | Simpler is better |
| 8 | `ZSH_NATIVE` | No bash, sed, awk, tr -- pure Zsh |
| 7 | `AESTHETIC_VIRTUE` | Exalt the excellent |

Axioms cascade: ABSOLUTE -> PROTECTED -> ADJUSTABLE. The system cannot override
an ABSOLUTE axiom regardless of instruction.

---

## Architecture

```
bin/master
└── Pipeline (intake * guard * executor * lint * render)
    ├── Executor          -- ReAct * PreAct * ReWOO * Reflexion
    ├── Enforcer          -- 14 layer checks + beauty scoring
    ├── Chamber           -- 12-persona echo chamber council
    ├── LLM               -- Replicate primary * OpenRouter fallback chain
    ├── GroundedContext   -- Loads own source into every LLM call
    └── ProjectMemory     -- .master/context.yml across sessions

data/
├── axioms.yml            -- constitution
├── council.yml           -- 12 personas (each with distinct model)
├── models.yml            -- model registry with fallback order
├── design_codex.yml      -- structural rules, prose style, aesthetics
├── smells.yml            -- 40+ smell detectors
└── exemplars.yml         -- beautiful patterns, cited in LLM prompts
```

---

## Install

```zsh
git clone https://github.com/anon987654321/pub4
cd pub4/MASTER2
bundle install
export REPLICATE_API_KEY=r8_...
export OPENROUTER_API_KEY=sk-or-v1-...
bin/master
```

---

## Commands

```
hi                    -> talk to the LLM
scan [path]           -> enforce axioms
reflow <path>         -> reorder file by importance (inverted pyramid)
refactor [path]       -> LLM-guided multi-pass refactor
self                  -> run MASTER2 on itself
chamber <text>        -> 12-persona echo chamber debate
model <name>          -> switch model
models                -> list available models
goal <text>           -> set project goal (persists across sessions)
remember <text>       -> store a decision in project memory
context               -> show project goal and recent decisions
status                -> constitutional alignment dashboard
budget                -> cost summary
help                  -> full command list
```

---

## Graceful degradation

MASTER2 never errors out. When the primary model fails, it cascades:

```
claude-sonnet-4.6 (Replicate)
  -> deepseek-r1:free (OpenRouter)
  -> gemini-flash:free
  -> llama-3.1-8b:free
```

The degraded model name appears dimly in stderr. The conversation continues.

---

## Project memory

Goal and decisions persist in `.master/context.yml` -- injected into every
LLM system message, free or paid, across every session:

```
❯ goal build a Ruby constitutional AI assistant
❯ remember chose Replicate for cost control
❯ context
  goal: build a Ruby constitutional AI assistant
  * chose Replicate for cost control
```

---

## Beauty scoring

Every review pass emits a beauty score alongside violation count:

```
enforcer0: 2 violations -- DRY, NAMING_DRIFT
✦ 7
```

`✦ 7` means 7 beauty points detected: zen methods, perfect names, composable
chains. Exemplary patterns are stored in `data/exemplars.yml` and cited in
future LLM prompts as positive models.

---

## Constitutional alignment

`status` shows a sparkline per axiom -- how well the codebase *embodies* each
one, not just avoids violating it:

```
DRY              ████░  9/10
KISS             █████  10/10
INVERTED_PYRAMID ███░░  7/10
ZEN_METHOD       ███░░  6/10
```

---

## Platform

Primary: OpenBSD 7.8 * Zsh * Ruby 3.4  
Also runs on: Linux * macOS  
Shell scripts use only Zsh builtins -- no bash, sed, awk, tr, find, head, tail.

---

## Design principles

- **Unix**: one tool, one job, composable, no noise on stdout
- **Inverted pyramid**: public interface first, helpers last, everywhere
- **Strunk & White**: omit needless words in every name, comment, and message
- **Graceful degradation**: never raise to the user; always return something
- **Self-referential**: MASTER2 runs its own constitution on itself
