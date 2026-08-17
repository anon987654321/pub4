# Business-plan recovery note

> Paths below were written against the pub4 layout of 2026-06-26, before
> `DEPLOY/` was split into `RAILS/`, `OPENBSD/` and `STUDIO/`. Those three
> have been repointed. `DEPLOY/bp/`, `DEPLOY/sh/` and `DEPLOY/archive/` are
> left as written because they have no successor in this tree: the business
> plan generator and vulcheck were not carried over, which is the gap this
> document exists to record rather than an error in it.


Legacy source:

```text
pub/bplans/
```

Current target:

```text
DEPLOY/bp/
```

## Gap

`pub4` restored visible static pages, but not the old source-of-truth pipeline.

Legacy `pub` had a consolidated business-plan collection with:

- Norwegian hedge fund materials
- political initiatives
- Bergen self-governance
- NATO Arctic proposal
- policy analysis
- Ruby 3D-printing / aerospace manufacturing
- Rails ecosystem platform
- archived/sensitive material

`DEPLOY/bp/IMPLEMENTATION_SUMMARY.md` describes an implementation with:

```text
bplans/
├── __shared/template.html.erb
├── data/*.json
├── assets/images/
├── generated/*.html
├── generate.rb
├── index.html
└── README.md
```

But `DEPLOY/bp/README.md` now says:

```text
Static HTML/CSS/JS business-plan sites. No generator — hand-maintained pages.
```

That means the pipeline was lost after visible page restoration.

## Files to restore or rebuild

Minimum:

```text
DEPLOY/bp/generate.rb
DEPLOY/bp/__shared/template.html.erb
DEPLOY/bp/data/syre.json
DEPLOY/bp/data/speis.json
DEPLOY/bp/data/norwegianhedge.json
DEPLOY/bp/data/pubhealthcare.json
DEPLOY/bp/data/ragnhild.json
DEPLOY/bp/data/govt_bergen.json
DEPLOY/bp/data/nato.json
DEPLOY/bp/data/ai3.json
```

Legacy source references:

```text
pub/bplans/consolidated/README.md
pub/bplans/consolidated/norwegian_hedge_fund/
pub/bplans/consolidated/political_initiatives/
pub/bplans/consolidated/technology_ventures/
pub/bplans/technology/rails-ecosystem-overview.md
pub/bplans/__letters/
```

## Restore rule

Business plans should not be hand-edited forever.

Use structured data as the source of truth, render HTML deterministically, and
commit generated pages only when production needs static assets.

## Completion definition

This recovery is complete when:

- every `DEPLOY/bp/*.html` page has a matching structured source file,
- `ruby DEPLOY/bp/generate.rb` reproduces the static pages,
- the generator validates required Innovation Norway sections,
- old consolidated markdown docs are either archived here or mapped to the new
  structured source files.
