# MASTER2 extreme-strict project tree

This is a proposed repository layout for a MASTER2 variant with strict, explicit adherence to its axioms (single-responsibility modules, explicit policy boundaries, visible failures, and stage-oriented execution).

```text
MASTER2/
├── README.md
├── LLM.md
├── AGENTS.md
├── data/
│   ├── axioms.yml
│   ├── constitution.yml
│   ├── pipelines/
│   │   ├── default.yml
│   │   ├── review.yml
│   │   └── emergency.yml
│   └── prompts/
│       ├── system.md
│       ├── reviewer.md
│       └── repair.md
├── docs/
│   ├── architecture/
│   │   ├── pipeline.md
│   │   ├── enforcement.md
│   │   └── failure-contracts.md
│   ├── axioms/
│   │   ├── ABSOLUTE_SAFETY.md
│   │   ├── SELF_APPLY.md
│   │   ├── ONE_JOB.md
│   │   └── INVERTED_PYRAMID.md
│   ├── decisions/
│   │   ├── 0001-stage-ordering.md
│   │   └── 0002-error-surface.md
│   └── extreme-strict-project-tree.md
├── bin/
│   ├── master2
│   └── master2-doctor
├── lib/
│   ├── boot/
│   │   ├── env.rb
│   │   └── loader.rb
│   ├── pipeline/
│   │   ├── intake.rb
│   │   ├── guard.rb
│   │   ├── route.rb
│   │   ├── execute.rb
│   │   ├── lint.rb
│   │   ├── render.rb
│   │   └── orchestrator.rb
│   ├── policy/
│   │   ├── registry.rb
│   │   ├── evaluator.rb
│   │   ├── severity.rb
│   │   └── violations.rb
│   ├── enforcement/
│   │   ├── self_apply.rb
│   │   ├── stop_the_line.rb
│   │   └── degrade_gracefully.rb
│   ├── analysis/
│   │   ├── task_parser.rb
│   │   └── risk_classifier.rb
│   ├── executor/
│   │   ├── shell_runner.rb
│   │   ├── fs_runner.rb
│   │   └── transaction.rb
│   ├── review/
│   │   ├── static_checks.rb
│   │   ├── constitutional_checks.rb
│   │   └── report_formatter.rb
│   ├── logging/
│   │   ├── event_log.rb
│   │   ├── audit_log.rb
│   │   └── trace_ids.rb
│   ├── views/
│   │   ├── cli/
│   │   │   ├── success.erb
│   │   │   └── failure.erb
│   │   └── json/
│   │       ├── result.erb
│   │       └── error.erb
│   └── errors/
│       ├── base_error.rb
│       ├── policy_error.rb
│       └── execution_error.rb
├── scripts/
│   ├── check-axioms
│   ├── check-pipeline-shape
│   └── smoke
├── test/
│   ├── unit/
│   │   ├── pipeline/
│   │   ├── policy/
│   │   └── enforcement/
│   ├── integration/
│   │   ├── strict-halt_spec.rb
│   │   └── degrade-gracefully_spec.rb
│   └── fixtures/
│       ├── valid/
│       └── violating/
├── var/
│   ├── logs/
│   ├── runs/
│   └── db/
└── .github/
    └── workflows/
        ├── ci.yml
        ├── policy-gate.yml
        └── release.yml
```

## Design intent

- Put pipeline stages in one directory with one file per stage.
- Separate policy evaluation from execution to keep accountability clear.
- Make failure rendering explicit and structured for machine and human consumers.
- Keep guardrails and constitutional checks as first-class modules and CI gates.
