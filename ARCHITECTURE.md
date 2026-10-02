# pub4 architecture

pub4 remains one repository with four roots. Their jobs are distinct.

```
MASTER   = brain / constitution / observation / repair
RAILS    = product / people / data / presentation
OPENBSD  = machine / network / security / deployment
STUDIO   = sound / image / media / export
```

The repository is not rebuilt by copying old structure into a new name. The existing rules, law, tests, gates, contracts, runbooks, provenance and working media tools are retained while implementation is moved behind smaller boundaries.

## MASTER

Canonical layers:

```
core
observe
fix
io
model
runtime
```

Dependency direction:

```
data / law
    |
  core
    |
  +-------+-------+------+
  |       |       |      |
observe  fix      io    model
  |       |       |      |
  +-------+-------+------+
             |
          runtime
```

Core does not depend upward. Observation never mutates. Planning never mutates. Repair mutates. Verification does not mutate.

`soul.yml` is the source for identity, sacred paths and absolute protection. `rules.yml` is the rule catalogue. Executable law remains under `law/`. The catalogue must never grow a second sacred-path authority.

## RAILS

`brgen` and `amber` remain real Rails applications. `shared/` contains only genuinely shared product primitives.

Domain ownership stays with the application that owns the noun. Shared messaging is a domain subsystem:

```
conversation
participant
message
attachment
event
delivery
```

Cross-tree access goes through explicit contracts. No RAILS code imports MASTER internals, OPENBSD internals or STUDIO internals.

The visual system has one shared interaction grammar. Dialects may change surface treatment, not the underlying interaction contract.

## OPENBSD

OPENBSD owns machine truth:

```
host
network
services
deploy
security
observability
verify
```

Deployment is one explicit lifecycle:

```
build -> stage -> verify -> install -> restart -> probe -> confirm
```

PF, relayd, NSD, rcctl, pledge, unveil, filesystem permissions and service ownership stay authoritative here. MASTER may inspect them, but does not silently redefine them.

## STUDIO

STUDIO owns media implementation.

```
dilla
visual
media
postpro
export
```

Dilla owns musical generation and measurement. Postpro owns image processing. LoRA/Replicate workflows belong here. MASTER dispatches and governs; it does not contain the media engines.

## Migration rule

Preserve first, then improve. Move physical boundaries before deleting behavior. Keep regression tests with the behavior they protect. A compatibility shim is acceptable only when it is explicit and temporary.

Generated output, vendored code, snapshots and machine state are not authored architecture.

## Proof

The clean architecture is not complete until:

- the four roots have single responsibilities;
- no sibling imports another tree's internals;
- sacred-path ownership has one source;
- MASTER core has no higher-layer dependency;
- observation/repair mutation boundaries are executable;
- RAILS shared code is actually shared;
- OPENBSD has one authoritative deployment path;
- STUDIO owns media implementations;
- migrated behavior retains regression coverage;
- semantic coverage is reported honestly;
- runtime and rendered gates are watched, not inferred.

The current migration is deliberately incremental inside pub4. The old pub5 experiment is not an active target.


## Boundary enforcement

Runtime code does not require sibling implementation files. MASTER's observation and gate tooling may read sibling source as evidence, but it does not become a product dependency.

RAILS keeps brgen, amber and bsdports as ordinary Rails applications. Cross-tree product calls use explicit adapters under `RAILS/contracts/`.

MASTER ingress is represented by `RAILS/contracts/master_client.rb`. Studio execution paths are represented by `RAILS/contracts/studio.rb`. These adapters expose the boundary; they do not load sibling internals.

Dilla child-process options live under `STUDIO/dilla/lib/process_spawn.rb`, so Studio's musical runtime is independent of MASTER's process-control namespace.


The current boundary is executable: MASTER may invoke STUDIO through the explicit media entrypoints, RAILS crosses to MASTER through the ingress contract and to STUDIO through `RAILS/contracts/studio.rb`, and neither product tree imports sibling implementation files.

STUDIO media ownership includes `dilla/`, `postpro/`, `replicate/`, `lora/`, and `visual/generators/`. `STUDIO/photograph.rb` is the canonical image/short-film entrypoint.


## Cognitive security grammar

MASTER extends the repository's OpenBSD design grammar upward. A model is proposal-only; each Effect carries a verb-derived capability; Constitution admits only capabilities present in the current context; capability sets can only shrink and may be locked.

The operating correspondence is:

```
pledge(2)   -> capability context
unveil(2)   -> Memory::View
sysctl      -> /status security
rcctl       -> /status services
syspatch    -> Fix::Patch over Fix::Transaction
dmesg       -> boot/event evidence
```

The rule is simple: machinery does not grant authority merely because it can perform an operation. Authority is declared, reduced, observed and verified.
