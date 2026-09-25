# Business plans

## Purpose

Bplans is MASTER's small declarative home for business-plan seeds and named
planning subjects. It is intentionally data-only: the files describe planning
targets; they do not execute a business, call a provider, or own application
state.

## Inputs

- YAML plan files under `MASTER/tools/bplans/`.
- A named plan key such as `ragnhild`, `space`, `syre`, or `weapons` when a
  caller selects one.

## Outputs

The canonical output is the selected YAML data. Consumers may turn that data
into planning documents, prompts, product briefs, or application work, but the
tool directory itself does not silently create external state.

## Invocation

The files are declarative inputs, not shell entry points. Read them through
MASTER's data/tool readers rather than inventing a second loader.

## Architecture

One directory, one source of truth, no duplicated business-plan schemas.
Application code remains in `RAILS/`; governance remains in `MASTER/`; these
files supply planning material only.

## Data and state

Tracked YAML is versioned planning source. Generated documents, credentials,
provider responses, and private customer data do not belong here.

## Security boundary

Treat plan content as untrusted data. Do not evaluate YAML as Ruby, interpolate
plan values into shell commands, or let a plan value select an arbitrary file,
constant, executable, host, or credential.

## Validation

MASTER's lexical and structural gates should verify parseability, duplicate
keys, path ownership, and reachability. An empty plan is allowed only when the
plan is deliberately a placeholder under an explicitly tracked work item; an
empty file must not masquerade as a completed business plan.

## MASTER integration

Bplans belongs to `MASTER/tools`, alongside the executable media and planning
utilities. It is not a plugin and not a top-level application tree.

## Failure modes

Malformed YAML, unknown plan names, inaccessible files, or empty required fields
must be explicit failures. No fallback may manufacture a plausible plan.

## Examples

```sh
ruby MASTER/bin/master "inspect the ragnhild business plan"
```

Use `MASTER/tools/bplans/` in new references; there is no retired STUDIO path.
