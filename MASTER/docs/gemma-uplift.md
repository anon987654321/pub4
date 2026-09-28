# Gemma uplift

MASTER now has an explicit operator ABI plus a training and evaluation loop for making a Gemma checkpoint intrinsically better at MASTER work.

The operator ABI is the inference-time scaffold. It establishes tree-first orientation, Ruby-first file work, zsh-only shell operation, argv subprocesses, readable commands, and evidence before completion.

The uplift corpus records verified trajectories: task, model, ordered tool events, outcome, and verification state. Local trajectory data belongs under .master/gemma and should not be committed when it contains private prompts or secrets.

The benchmark checks tree-first behavior, shell discipline, argv subprocesses, read-before-write, and verification.

The training loop is teacher trajectories, verification filtering, dataset export, supervised fine-tuning, held-out evaluation, and artifact promotion. Preference learning can use verified trajectories as positives and failed or policy-violating trajectories as negatives. Reinforcement learning can use the benchmark as a reward signal.

Google documents supervised fine-tuning and parameter-efficient methods for Gemma; MASTER exports a framework-neutral corpus instead of adding a Python ML runtime to the OpenBSD-oriented Ruby system. The weight update itself happens in the external training environment. The resulting checkpoint returns to MASTER only after the same benchmark is passed.

Commands:
  ruby MASTER/tools/gemma_uplift.rb contract
  ruby MASTER/tools/gemma_uplift.rb manifest
  ruby MASTER/tools/gemma_uplift.rb score .master/gemma/trajectories.ndjson
  ruby MASTER/tools/gemma_uplift.rb record trajectory.json
  ruby MASTER/tools/gemma_uplift.rb export .master/gemma/trajectories.ndjson .master/gemma/export.ndjson
