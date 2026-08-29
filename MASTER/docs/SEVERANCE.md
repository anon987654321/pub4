# Severance Record

What `core/` is, what was cut to build it, and why the cutting stopped. This is
a record, not a plan. It was `ABSORPTION.md`, a migration chart whose stated
invariant was "the spine never grows — everything that is neither a verb nor a
rule is accretion and dies." Three weeks of commits falsified that:

| | 2026-07-09 (`e6f3e9b22`, core lands) | 2026-07-30 | Δ |
|---|--:|--:|--:|
| `lib/` | 39,696 lines | 47,732 | **+8,022** |
| `core/` | 823 lines | 823 | **0** |

`review` +1,979, `cli` +1,519, `ground` +1,503, `io` +731, `voice` +638, `fix`
+497 — every subsystem the chart listed as dying, growing. That is not a failure
of discipline; it is what shipping an interactive agent looks like. But a plan
nothing has moved toward in three weeks is a description of the past, so it is
written as one here, and `DECISIONS.md` — which already frames the two spines as
deliberate and permanent — is the standing policy. The two documents used to
contradict each other, with `AGENTS.md` pointing agents at this one.

## The four concepts

```
core/
  master.rb        vocabulary: Effect, Verdict, Observation, Secret, VERBS
  constitution.rb  the gate: load rules, admit/revise/block each Effect
  world.rb         the effects: read write exec git — the ONLY door to reality
  memory.rb        the record: turns + evidence the Model reasons from
  core.rb          the fold: propose → admit → perform → observe → repeat
  model.rb         the one LLM method: Memory → next Effect (done)
```

> Fold proposed **Effects** through a **Constitution** that admits each one
> before it touches the **World**, keeping the **Memory** the model reasons from.

Inside `core/` that shape still holds and should keep holding: a new ability is
a new Effect verb plus its handler in `world.rb`; a new constraint is a new rule
in `constitution.rb`. `rake lint:spine` enforces the rest — `lib/` may shrink or
hold, never grow past its recorded ceiling. That is the invariant this document
used to assert and never measured.

## What was actually severed (permanent)

- **Media generation**: ~9.3k lines / 141 files — video, LoRA, comfyui,
  repligen, postpro, social_sim, motion_critique, their CLI/boot wiring, tools
  and assets. Kept the dual-use `ReplicateClient` + `replicate_kokoro` TTS
  (production voice) and `SubdomainOrchestrator` (deploy). Re-severed 2026-07-14
  (`76b11fec4`) after a 2026-07-08→09 reintroduction; confirmed permanent by
  operator decision 2026-07-15. If the Ragnhild LoRA loop needs generation
  again, express it as `core/world.rb` handlers — do not restore
  `lib/io/lora_pipeline.rb` or `video_chain.rb`.
- **Five dead subsystems**: `eval_harness`, `prompt_evolver`, `system_pressure`,
  `soul_proposals`, `opportunity_surface`.

## What survived a severance attempt, and why

The kill list in the old chart was written from names, not references. A sweep
found most of it load-bearing in the live `lib/` boot:

- **`bedrock_stub`** is not accretion — it pre-defines the RubyLLM Bedrock
  constant so ruby_llm never autoloads `openssl.so`.
- **`semantic_cache` / `semantic_index` / `embeddings` / `mcp_coordinator`** are
  wired into the live agent stack (`ai_boot` adds `infra[:mcp].tools`; `cache:`
  flows into `Review::Agent`).
- **`cli/`, `fix/`, and `review/`'s agent stack** are the deployed product: the
  interactive streaming REPL, the dashboard at ai.brgen.no, sessions, TTS,
  standing orders, the event bus. The Fold expresses their *essence* in ~800
  lines, but it is a batch runner, not an interactive REPL. Replacing them was
  never mechanical severance; it was a product decision to delete shipped
  surface.

## How the two spines are joined

**Bridge, decided 2026-07-09.** `TurnRouter` is the single agent entry: plain
language and `/run <goal>` → `CoreBridge` → `Fold`; slash commands →
`command_registry`. Wired in the CLI, web `ChatService`, `Gateway`, and standing
orders. Regex workflow fan-out in `repl_flow` is gone — one goal, the Fold
decides.

- **Deliberation** (2026-07-09): conditional hybrid on `TurnRouter`. `FoldRisk`
  classifies goals; medium+ runs `Ideation` (3–5 approaches + synthesis);
  high-risk requires the `critique` verb (in-process `Deliberation` tribunal)
  before `done`. The Constitution enforces ideation notes and council clearance.
- **Runtime** (2026-07-09): `build_runtime` replaced `build_pipeline`; container
  `:pipeline` is a `TurnPipeline` adapter over `TurnRouter`, and legacy stages
  no longer boot. `lib/cli/pipeline.rb` remains for smoke tests only.
- **Lean boot** (2026-07-09): default; `MASTER_FULL_BOOT=1` for the full
  swarm/council_stage/graph fan-out/propose_tree. VPS rc.d already sets
  `MASTER_WATCHER=0`, `MASTER_AUTOFIX=0`.

## If absorption restarts

It would be a product decision, not a refactor, and it needs a sponsor and a
target date rather than a chart. The order that was worked out — World handlers,
then the rules that gate them, then Memory, then budget/rollback, then a thin
CLI, then severing peripherals — is in this file's history (`git log core/`).
Nothing above prevents it. What is no longer claimed is that it is in progress.
