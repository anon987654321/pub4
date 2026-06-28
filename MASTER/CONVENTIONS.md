# Conventions

External LLM orientation is `/orient conventions`. Scan law is `data/rules.yml` and generated `data/CANON.md`. Operator runbook: `DEPLOY/OPERATOR.md`.

Data boundaries:

- YAML is operator-facing configuration and uses string keys.
- JSON runtime state may use symbol keys only when its reader requests `symbolize_names: true`.
- Every versioned YAML registry declares a top-level integer `schema`; readers must ignore that metadata key.
