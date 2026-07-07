# Rule Shards

These files stay split by scanner scope. Merging them into `data/rules.yml` would hide the consumer boundary and make PROXIMITY worse.

- `line.yml` -> line-level scanner rules.
- `file.yml` -> file-level scanner rules.
- `unit.yml` -> method/class/unit scanner rules.
- `codebase.yml` -> repository-wide scanner rules.

Related rule-like registries outside this directory are also intentional:

- `data/design_rules.yml` -> `Master::Design`.
- `data/llm_output_rules.yml` -> `Master::Judge::OutputCheck`.
- `data/rule_deps.yml` -> `Master::Loop::FixLoop` rule ordering and dependency checks.
