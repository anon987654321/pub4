# Rails apps

**Four Rails apps, one shared engine, and one process that answers to a hundred
hostnames, each built so that a stranger on a phone sees a single, quiet product
and never the machinery beneath it.** brgen is the city network, amber is the
wardrobe, bsdports is a search of the ports tree, and master is MASTER's face
on `ai.brgen.no`. They run on SQLite behind
Falcon, on one box called vm23, and everything they share lives in one engine
so that a fix made once is made everywhere.

This README is the entry to the tree. Feature truth is `apps.yml`, which also
holds the ports, the domains and the stack versions, so nothing here restates
them. Planned work that is not yet real sits in `apps.horizon.yml` and is
marked for agents to ignore. Work only the operator can finish is listed in
`MASTER/data/operator_seams.yml`. Rules for working in the tree are in `CLAUDE.md` beside
this file,
and each app keeps its own contract in an `AGENTS.md`.

brgen is not a folder of apps. Every city apex in `Brgen::DomainRegistry` serves
the feed, and the verticals are engines reached on subdomains of that apex, so
`dating.brgen.no` and `dating.lsangeles.com` are the same code under two city
names. The verticals sit beside the host as directories named `brgen_` and the
vertical: dating, maps, marketplace, messenger and radio, which holds the playlist
and tv engines. Food ordering is nested inside marketplace. Anything that counts
brgen's code must read the host and every `brgen_*` directory, or it measures
about half the app and calls the result health. Read `brgen/AGENTS.md` before you
touch a vertical, and `brgen/README.md` before you add one.

The shared engine is the `pub4-shared` gem and lives in `__shared`. Each app
loads it by local path. On the box, the copy-tree deploy puts each app at
`/home/<app>/app` and gives it its own copy of the engine at `/home/<app>/shared`,
a sibling and never a subdirectory. Syncing to the wrong one makes the asset
precompile a silent no-op. `__shared/README.md` describes what the engine owns.
master does not mount the engine and is not copied: it runs in place under
`/home/dev/pub4/RAILS/master`, deployed by `OPENBSD/bin/vps_deploy_master.sh`,
and its own `CLAUDE.md` governs it.

Everything that builds, tests or probes these apps now lives under MASTER. The
old RAILS `bin` directory is gone, and its work moved into `MASTER/tools/rails`,
reached through the operator: `triangle` boots brgen, amber, bsdports and the
face on the ports the live checks probe, `premerge` runs the premerge proof, `ci`
runs each app's own `bin/ci`, and `coverage` runs the full coverage pass. Each app
also keeps its own `bin/ci` for RuboCop, Brakeman, bundler-audit and the tests.
The design tokens come from `MASTER/data/tokens.yml`, and the shared engine's
`design_tokens.yml` is a file generated from it, not a second source.

Production is one box. A deploy sheds amber and bsdports, and relayd keeps
answering TLS with their ports closed, so the outage looks like a hang and not a
server error. The deploy command restores them. If you deploy by hand, check
ports 61352 and 47312. Health is `/up` for liveness and `/health` for the depth of
Solid Cache, Solid Queue and the database. Secrets live in `/etc/<app>.env` on the
box, and no `config/master.key` is in git. `_deploy.sh` is the orchestrator,
`deploy.sh` a thin shim, and each app's own script sources the shared contract.
The apps default to Norwegian, so tests assert through I18n keys and never through
English literals.

Strict loading is on in every environment. Reading a lazy association off a record
fetched by id raises in test and in production, so check that before you report a
server error. Money is stored as integer minor units.

The checks are rows in `MASTER/checks/checks.yml`, run by `MASTER/checks/runner.rb`,
which can list them. Most run in process. The source checks read text, and the
rendered checks drive Chrome over the DevTools Protocol with a small stdlib
session, and measure what the browser laid out. Without Chrome the rendered checks
degrade to warnings, so a green run is not by itself evidence that anything was
measured. A check can only see what it globs. Shared views once sat outside every
check because the page inventory read each app's views and never the engine's, and
the inventory now names them explicitly.

Media work goes through the contract in `MASTER/contracts/studio.rb`. STUDIO owns
postpro, replicate and dilla, and Rails does not load their classes. Provider
tokens belong in the app's env file on the box and never in credentials or source.
All three apps compile the same service worker from the engine's `pwa` directory,
and the styled error pages in the engine's `public` directory are copied into each
app at deploy.

## Visual identity

The shared contract is `MASTER/data/laws.yml#visual_identity_contract`, and its
values are generated from `MASTER/data/tokens.yml`. Shared hierarchy and the
semantic signal may travel across apps; product dialects do not collapse into one
palette. Brgen retains its local editorial identity, Amber protects garment colour
and neutral presentation, and BSDPorts keeps its ultra-minimal white, classic-Google-style
search surface with Arial and blue result links. MASTER's face uses the signal on ink.
master shares Brgen's brand character by the operator's decision, recorded in `apps.yml`;
its pages still render only the face's own stylesheet. Review generated assets and
rendered screenshots, not source tokens alone.

## Monetisation and the ad visual contract

Advertising is governed, not sprinkled. MASTER audits rendered ads against
`tokens.yml#ad_visual_contract` through `MASTER/tools/visual/audit_ad.rb`
(rake task `ad_visual_audit`); this tree binds the source partials to the same
contract in `test/ad_visual_contract_test.rb`. The two surfaces carry their
disclosure differently and both ways are contractual: `_ad_slot` (AdSense)
renders nothing without an advertising-consent signal and labels itself
through `t("shared.advertisement")`; `_affiliate_feed_unit`
(Tradedoubler/Amazon) renders the `affiliate_disclosure` partial, marks every
outbound link `rel="noopener sponsored"`, and carries a per-link paid-link
mark. No ad partial may hard-code a hex color — every value resolves through
the token contract. The affiliate stack it binds to lives in the shared
engine: `Shared::Tradedoubler`, `AffiliateProduct`, `AffiliateVoucher` and
`AffiliateConversion`.

## Running it

```zsh
ruby MASTER/checks/runner.rb --list
ruby MASTER/checks/runner.rb --all
MASTER/bin/operator triangle up
MASTER/bin/operator premerge --list
cd RAILS/brgen && bin/ci
```


## Public-page metadata contract

The central rendered `surface_schema` check measures the existing Brgen home, marketplace, cart, dating and messenger surfaces for unique title, description, absolute canonical URL, and Open Graph title/description/URL. The corresponding positive fixtures carry complete metadata, and focused MASTER tests prove missing/duplicate/relative metadata is rejected. These contracts do not yet replace the outstanding live audit of every owned hostname, alias redirect, robots.txt, sitemap and JSON-LD document in the repository TODO.


## Response security headers

The RAILS contract suite also rejects literal JSON-LD `<script>` elements in view templates; views must use `SchemaHelper`/`Shared::SeoKit#json_ld_script`, whose serializer escapes HTML-significant characters before marking the JSON safe. The existing helper-level test covers a `</script>` payload. The root check runner's `security_headers_source` contract checks the shared Rails security-header initializer, relayd's edge headers, and both nonce-CSP initializers. CSP must remain app-owned: a global relayd CSP can replace the app's nonce-bearing policy and break the MASTER face. The check does not claim production enforcement; `PUB4_CSP_ENFORCE=1` remains a live operator change and must be verified against real vm23 response headers.
