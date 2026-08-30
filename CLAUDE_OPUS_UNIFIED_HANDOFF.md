# Claude Opus: unified pub4 implementation handoff

Dear Claude Opus,

You are receiving this patch as a consolidation layer for the work discussed
with the repository owner across the recent pub4 analysis sessions. Please
treat it as an implementation brief, not as permission to invent a second
architecture.

The goal is to turn the accumulated analysis into one coherent, reviewable
implementation pass across `MASTER`, `RAILS`, monetisation, the Amber/Wardrobie
product surface, testing, and repository hygiene.

There are two rules above everything else:

1. Preserve existing behaviour unless a change is explicitly required below.
2. Reconcile every change against the current tree before applying it. Do not
   blindly paste historical snippets over newer code.

The current repository already has a constitutional hierarchy:

`MASTER/data/soul.yml` > `MASTER/data/rules.yml` > `CLAUDE.md`

Respect that hierarchy. Keep contracts in their owning subsystem instead of
creating duplicate sources of truth.

## 1. Mission

Perform a single coherent hardening and completion pass that:

- closes the highest-value testing gaps;
- removes incomplete/dead logic where it is demonstrably dead;
- repairs missing or inconsistent Rails views, stylesheets, routes, and
  product wiring;
- strengthens MASTER's orchestration, validation, recovery, and agent safety;
- improves monetisation without degrading the free/core product;
- turns the Amber/Wardrobie product surface into a deliberate, coherent
  product rather than a partially migrated Rails application;
- makes deployment and operator behaviour observable and reversible;
- leaves a clear testable contract for every newly introduced capability.

Do not perform cosmetic churn merely to make the diff large.

## 2. Current architectural constraints

The repository's existing guidance identifies:

- `MASTER/` as the constitutional AI runtime in Ruby;
- `RAILS/` as the Rails 8 application collection;
- `OPENBSD/` as deployment/operator infrastructure;
- `STUDIO/` as media tooling;
- `bin/master` as the repo-wide MASTER instruction surface;
- `bin/pub4` as the operator surface.

Preserve the two-surface model. Do not resurrect the deleted top-level
`bin/cli` compatibility surface.

Use the existing project conventions:

- Ruby/Rails first;
- Rails 8;
- Hotwire/Turbo/Stimulus where already established;
- esbuild + Propshaft where already established;
- PostgreSQL/Redis where already established;
- OpenBSD-native deployment assumptions;
- no Docker;
- do not introduce Python or GNU-only shell tooling into repository scripts;
- double-quoted Ruby strings and two-space indentation.

## 3. MASTER: constitutional/runtime hardening

### 3.1 Validate every contract at the boundary

Audit MASTER's data-driven contracts and make malformed input fail clearly,
early, and deterministically.

At minimum inspect:

- `MASTER/data/soul.yml`
- `MASTER/data/rules.yml`
- agent/persona definitions
- workflow definitions
- scanner/fix-loop configuration
- snapshot/rollback configuration
- YAML schemas and validators

The implementation must distinguish:

- malformed data;
- missing required data;
- unknown keys;
- unsupported values;
- runtime failures;
- expected policy rejection.

Errors should name the exact file, key/path, and actionable correction.

### 3.2 Repair the known circuit-breaker dependency hazard

There has previously been a `Stoplight::Light` `NameError` in MASTER's LLM
layer. Verify the current tree rather than assuming the historical state is
unchanged.

If the dependency is still required:

- declare it explicitly;
- load it through the normal dependency path;
- add a regression test that boots the affected path;
- test open/closed/half-open or equivalent states actually used by the code.

If the code has since moved away from Stoplight, remove stale references and
test the replacement instead.

### 3.3 Reduce require-order fragility

Earlier analysis identified a large number of `require_relative` edges and a
loader structure that made boot order fragile.

Do not mechanically rewrite every require.

Instead:

- map the dependency graph;
- identify cycles and order-dependent constants;
- make ownership explicit;
- use normal Ruby autoloading/loading conventions where appropriate;
- add a clean-boot test that exercises the public entry point;
- add a second test that loads the relevant component in isolation where that
  is a supported contract.

### 3.4 Snapshot rollback

Complete or harden snapshot rollback if the current implementation is
incomplete.

Required properties:

- atomic snapshot creation;
- explicit snapshot identity;
- deterministic restore;
- validation before activation;
- refusal to restore incompatible schema/data;
- clear rollback logs;
- failure leaves the previously valid state intact;
- tests for interrupted/partial restore.

Do not claim transactional semantics unless the underlying implementation
actually provides them.

### 3.5 Autoloop fencing

Complete the missing safety boundary around autonomous/fix-loop execution.

The loop must have:

- bounded iterations;
- explicit stop conditions;
- no recursive runaway;
- durable run identity;
- a way to detect stale/dead sessions;
- a way to prevent two sessions from mutating the same protected state;
- clear operator-visible termination reasons.

Tests must cover:

- normal completion;
- validation failure;
- repeated identical failure;
- stale session;
- maximum iteration exhaustion;
- concurrent-start rejection.

### 3.6 Dead-session startup

Earlier work identified dead-session startup behaviour and missing data files
referenced by workflow/agent documentation.

Audit all startup references and ensure:

- every required file is either present or created by an explicit bootstrap;
- optional files are treated as optional;
- stale paths are removed;
- startup errors distinguish "missing required" from "empty optional";
- a dead/stale session cannot silently masquerade as a fresh healthy session.

Add regression tests for each startup state.

## 4. MASTER: multi-agent safety

The current `CLAUDE.md` correctly warns that one shared git index is unsafe.
Preserve and strengthen that model.

The implementation should:

- prefer `bin/pub4 worktree <name>` for concurrent work;
- retain path-scoped commit guidance;
- retain the cross-tree commit guard;
- retain the push guard;
- expose pending commits before push;
- make session identity explicit where practical;
- never claim that a path alone identifies an agent/session.

Where hooks already exist, test them as executable behaviour rather than
documenting them only.

Add tests for:

- cross-tree commit refusal;
- explicit override;
- multi-commit push refusal;
- explicit push override;
- clean single-commit path;
- useful diagnostic output.

## 5. MASTER: LLM routing and resilience

Audit the current LLM routing rather than recreating historical configuration.

The accumulated architecture has used role-specific routing such as:

- security audit -> security-focused model;
- code generation -> coding-focused model;
- research -> research-focused model;
- PR review -> review-focused model.

Keep routing policy data-driven.

Add:

- provider/model validation;
- timeout handling;
- retry/backoff limits;
- rate-limit handling;
- circuit breaking;
- deterministic fallback policy;
- structured failure telemetry;
- tests for each routing branch.

No silent provider substitution when policy requires a specific model.

## 6. RAILS: deep completion audit

Perform a full Rails application audit rather than limiting the work to
controllers/models.

Inspect:

- routes;
- controllers;
- models;
- service objects;
- jobs;
- mailers;
- policies/authorization;
- views;
- partials;
- layouts;
- helpers;
- Stimulus controllers;
- Turbo frames/streams;
- JavaScript entry points;
- stylesheets;
- asset pipeline configuration;
- PWA manifest/service worker;
- database constraints and indexes;
- seeds;
- request/system/model/service tests;
- accessibility;
- error pages;
- authentication and authorization boundaries.

For every discovered feature, trace:

`route -> controller -> policy -> model/service -> view -> JS/CSS -> test`

Any missing edge should be either implemented or explicitly documented as
intentional.

## 7. RAILS: tests are a product feature

Prioritize tests that prove behaviour rather than merely increasing line
coverage.

Minimum high-value matrix:

### Authentication

- sign in;
- sign out;
- invalid credentials;
- session expiry;
- authorization boundaries;
- account recovery if present;
- OAuth/Vipps/Google/Snapchat flows if present in the current tree.

### Core product flows

- create/read/update/delete for core resources;
- validation errors;
- authorization;
- empty states;
- pagination/filtering;
