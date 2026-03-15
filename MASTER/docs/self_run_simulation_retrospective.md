# MASTER full self-run simulation and retrospective

## Objective

Simulate a full self-run and then reflect on how MASTER could have done better.

## Simulation command

```bash
MASTER2/bin/master selfrun --deep
```

## Observed result

The run failed during boot before any self-run phases executed.

Key failure signals:

1. Dependency auto-install attempted `gem install` and received repeated `403 "Forbidden"` responses.
2. Runtime then aborted with `LoadError: cannot load such file -- ruby_llm` from `MASTER2/lib/llm.rb`.
3. Because boot failed in dependency loading, the self-run pipeline (`run_phase1..run_phase4`) never started.

## What MASTER could have done better

### 1) Add explicit preflight before full self-run

Before entering self-run, MASTER should run a hard preflight that verifies:

- Required gems are already available.
- Required API credentials are present and valid.
- Network access to gem/provider endpoints is healthy.

If preflight fails, exit with one compact diagnosis block and remediation steps.

### 2) Fail once, not repeatedly

The current flow retried gem install failures and emitted large repeated stacks. A circuit breaker for dependency installation should:

- stop after first deterministic auth/permission error (403/401),
- summarize root cause,
- avoid noisy duplicate logs.

### 3) Provide degraded offline self-run mode

A `--offline`/`--no-llm` mode should still run:

- syntax checks,
- static linting,
- local rule/axiom scans,
- diff-risk reporting.

That would keep self-run useful when network/provider access is blocked.

### 4) Improve startup diagnostics

Boot should print an ordered readiness table (gems, keys, providers, file permissions) before any heavy init. This helps operators see what is broken in seconds.

### 5) Add regression tests for startup resilience

Add tests for:

- forbidden gem source responses,
- missing `ruby_llm` dependency,
- graceful fallback messages,
- self-run never entering phase execution when boot is unhealthy.

## Proposed minimal improvements backlog

1. Implement `MASTER::Preflight.check!` and call it from `bin/master` before `run_selfrun`.
2. Add install-error classification in `MASTER::AutoInstall` (`auth`, `network`, `missing package`) with short summaries.
3. Add `selfrun --offline` path with local scanners only.
4. Add targeted tests around failure classification and self-run guardrails.

## Retrospective summary

The simulation did its job by exposing boot fragility. The biggest improvement is to shift failure earlier and make it intentional: preflight-fast, fail-clean, and degrade usefully when LLM dependencies are unavailable.
