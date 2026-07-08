# Absorption Map

How `lib/` (43.6k lines, 14 subsystems) folds into `kernel/` (662 lines, 4 concepts).
This is the chart for the kernel-first rebuild: every migration slice moves one
piece of essential behaviour into the fold and deletes the subsystem it came from.

## The invariant

The spine never grows. There are exactly four concepts and one sentence:

> Fold proposed **Effects** through a **Constitution** that admits each one before
> it touches the **World**, keeping the **Memory** that the model reasons from.

So absorption is not "move 43k lines into `kernel/`." It is:

- **New ability** → one new **Effect verb** + its handler in `world.rb`. Nothing else.
- **New constraint** → one new **rule** in `constitution.rb`. Nothing else.
- **Everything that is neither** (pipelines, councils, scanners, orchestrators,
  registries, telemetry, speculative media tooling) is **accretion and dies.**

A subsystem is absorbed when its *essence* is re-expressed as a handler or a rule
and its files are deleted — not when its code is relocated.

## Target shape

```
kernel/
  master.rb        vocabulary: Effect, Verdict, Observation, Secret, VERBS
  constitution.rb  the gate: load rules, admit/revise/block each Effect
  world.rb         the effects: read write exec git — the ONLY door to reality
  memory.rb        the record: turns + evidence the Model reasons from
  kernel.rb        the fold: propose → admit → perform → observe → repeat
  model.rb         the one LLM method: Memory → next Effect (done)
```

Growth is allowed only inside `world.rb` (a handler per verb) and `constitution.rb`
(a rule per constraint). No new top-level files without a new concept — and there
are no new concepts.

## Where each subsystem lands

| lib/ subsystem | lines | essence that survives | destination | what dies |
|---|--:|---|---|---|
| `reach/` | 6656 | read/write/exec/git/search/path-guard primitives | **World handlers** | lora, comfyui, replicate, video, social_sim, subdomain, bedrock, semantic index/cache, mcp — media & infra accretion |
| `judge/` | 10621 | the rules that gate effects; "run a check, weigh evidence" | **Constitution rules** + `exec` evidence | scanner engine, council, swarm, consensus, reflexion, embeddings, graph/ref/repo maps, prompt_evolver, code_index |
| `now/` | 7933 | "propose the next step, act, report" | **Fold + Model** | multi-stage pipeline, command_registry, routing, orchestration, opportunity_surface, web_server |
| `ground/` | 6565 | sandbox/taint/secret/axiom **rules**; memory & evidence store | **Constitution rules** + **Memory** | brain_overlay, brutalist_minimalism, cluster_registry, attention_context, dozens of one-off policies |
| `voice/` | 3260 | (peripheral) TTS | **stays lib**, or an optional `exec` | — |
| `loop/` | 3014 | rollback; a single budget check | **World rollback** + one Fold guard | governor, homeostat, heartbeat, system_pressure, propose_tree, conflict_resolver, watch/rule/fix loops |
| `trace/` | 2263 | one Observation stream | **Memory / Observation** | event-bus glob routing, telemetry fan-out |
| `rails/` + `web/` | 758+ | (peripheral) dashboard | **stays**, separate deliverable | — |
| `providers/` `grok/` | 378 | pick a model, get a chat | **Model** (done) | provider registry ceremony |
| `builder/` | 226 | construct the fold | **bin + Fold.new** | boot_phases, ai_boot |
| `pub4/` | 327 | (peripheral) pub4 checks | **stays**, own tool | — |
| `ops/` `deploy/` `design/` | 609 | (peripheral) process/deploy | **stays**, scripts | — |

Peripherals (`voice`, `rails/web`, `pub4`, `ops`, `deploy`, `design`) are *not*
accretion — they are real, separate programs. The kernel does not absorb them; it
stops depending on them. When they need to act on the world they go through an
`exec` Effect like any other caller.

## Migration order

Dependency-first, each slice shippable and green. World handlers before the rules
that gate them; rules before the fold leans on them; Model last (done early because
it unblocks dogfooding).

0. **Model adapter** — real LLM → next Effect. *(done: `bea84fda6`)*
1. **World: read/write/exec/git handlers.** Absorb the ~15 real primitives from
   `reach/` (`read_file`, `write_file`, `str_replace`, `exec`, `shell`, `list_dir`,
   `tree`, `search_files`, `git_operations`, `path_guard`, `atomic_write`,
   `whitespace_normalizer`). Delete the media/infra half of `reach/`.
2. **Constitution: the gating rules.** Absorb `ground/{sandbox_policy, taint,
   redactor, immutability, pledge, done_checker, axioms}` as rules. Delete the
   scanner engine; deep static analysis becomes an `exec` evidence source, not a
   kernel subsystem. Fold `judge/{commit_guard, output_check, verdict}` into Verdict.
3. **Memory: turns + evidence.** Absorb `ground/{memory, evidence, checkpoint,
   unfinished_ledger}` and collapse `trace/` to a single Observation stream.
4. **Fold: budget + rollback.** Absorb `loop/rollback` into World's transaction and
   the HostBudget guard into one Fold check. Delete the rest of `loop/`.
5. **CLI: thin shell.** Reduce `now/cli` + `command_registry` to a dispatcher over
   `bin/master-kernel`. Delete `now/` pipeline/stages/routing.
6. **Sever peripherals.** Point `voice`, `rails/web`, `pub4`, `ops` at the kernel via
   `exec`; delete their reach-into-lib couplings. `lib/master.rb` becomes a shim,
   then goes.

Each slice: absorb essence → prove green (`rake test:kernel`, kernel smoke,
`bin/master-kernel "dogfood noop"`) → delete the drained files → commit.

## Kill list (dies, does not move)

Verified per-file for live references at migration time (the Phase 1 method), but
these carry no coding-agent role and are expected to delete outright:

- **reach media/infra:** `character_lora_*`, `motion_lora_*`, `comfyui_client`,
  `replicate_client`, `repligen*`, `video_*`, `postpro`, `social_sim/`,
  `subdomain_orchestrator`, `bedrock_stub`, `relayd`, `generation_prompt_refiner`,
  `semantic_index`, `semantic_cache`, `mcp_coordinator`.
- **judge multi-agent & indexing:** `council/`, `swarm/`, `consensus`, `reflexion`,
  `prompt_evolver`, `embeddings`, `graph_retriever`, `reference_graph`,
  `code_index/`, `repo_ecology/`, `repo_map`, `ast_signature`, `eval_harness`.
- **loop control theatre:** `governor`, `homeostat`, `heartbeat`, `system_pressure`,
  `propose_tree`, `conflict_resolver`, `soul_proposals`.
- **now pipeline:** `pipeline`, `stages/`, `orchestration/`, `routing/`,
  `opportunity_surface`, `tribunal_feedback`, `web_server`, `web_secret`.
- **ground one-offs:** `brain_overlay`, `brutalist_minimalism`, `cluster_registry`,
  `attention_context`, and the long tail of single-use `*_policy` / `*_registry`
  files whose rule (if any) belongs in `constitution.rb`.

## Done

The kernel is finished when `lib/` holds only peripherals that reach the world
through `exec`, and the agent's entire ability-and-constraint surface is: the verbs
in `world.rb` and the rules in `constitution.rb`. Adding a capability then means
adding a handler; adding a limit means adding a rule; and the spine is still one
sentence.
