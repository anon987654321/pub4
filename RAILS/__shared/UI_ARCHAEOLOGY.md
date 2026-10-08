# UI archaeology carried into pub4

## pub → pub4

The oldest recovered brgen Rails app in pub (brgen_app/) used a Bootstrap-era language: bordered cards, shadowed hover states, dense metadata, explicit form helpers and a separate action row. The useful idea is information order—author/meta, title/body/media, then actions. Pub4 keeps that order while removing framework chrome.

The old post form also carried character counters, reading-time feedback and image preview/removal. Pub4 already has a shared character-counter and Tiptap pipeline; the recovered principle is timely feedback rather than inline legacy JavaScript.

The old post detail uses a strong title → author/meta → media → body → interaction rhythm. Pub4 keeps the rhythm while consolidating interactions through shared action/vote partials.

## pub2 → pub4

rails/amber_home_style.css is the clearest early Amber visual statement: centered hero, oversized identity, large headline, one primary action and a deliberate feature grid. It also contains gradients, drop shadows and decorative animation. The recovered principle is editorial pacing and hierarchy; the decorative elevation is intentionally discarded.

The old BRGEN marketplace and playlist generators establish a useful split between catalogue discovery and item detail, plus playlist queueing, sharing, comments and collaboration. Those ideas map into the current marketplace and Radio anatomy instead of copying the old framework code.

## pub3 → pub4

The shared Rails layout in rails/__shared/layouts/application.html.erb is a useful ancestor of pub4's landmark skeleton: skip link, navigation, main content, flash region and footer.

rails/__shared/layouts/visualizer.css is especially valuable: fullscreen canvas, safe-area variables, small fixed chrome, focus styling and explicit shadow removal. Pub4's Radio surface keeps that low-chrome discipline while using the current playlist/tunnel implementation and token system.

## archive inventory

Catalogued historical snapshots include pub/__OLD_BACKUPS/BRGEN_OLD.zip, brgen_ANCIENT_20240622.tgz, rails_amber_20240803.tgz, rails_amber_20240804.tgz, rails_amber_20240806.tgz, rails_brgen_20240804.tgz, rails_brgen_20240806.tgz, rails_brgen_marketplace_20240804.tgz, rails_brgen_marketplace_20240806.tgz, rails_brgen_playlist_20240804.tgz, rails_brgen_playlist_20240806.tgz and corresponding dating/takeaway/tv snapshots.

The connected GitHub file API exposes repository text and Git objects but did not provide a safe binary decompression path in this session. Archive blobs were catalogued and cross-checked against expanded/textual descendants; no binary archive payload was copied into pub4.

## implementation rule

Selective carryover only: preserve ideas, not historical dependencies. The current shared token system, Rails partials and MASTER minimalism contracts remain authoritative.


## final salvage pass

The final text-corpus pass found four genuinely missing executable invariants and one further semantic invariant:

- `README_VISION`: the root README leads with a concise project vision rather than setup choreography.
- `INTERACTION_SEMANTICS`: navigation is an anchor, an action is a button, and native semantics beat clickable generic elements or ARIA used to repair the wrong element.
- `CONFIGURATION_SHAPE`: configuration stays shallow and consolidated; the historical depth/section limits are structural ceilings, not visual-token values.
- `STYLE_FOLLOWS_STRUCTURE`: semantic structure and information hierarchy are corrected before selector complexity or decoration is added.
- `HTML_HEADING_HIERARCHY`: headings express document hierarchy without skipped levels or using tags as visual-size shortcuts.

The old `master.json` backup under `pub/__OLD_BACKUPS` was also checked. Its 2025-07 snapshot belongs to a different `pubhealthcare` framework branch and carries general ideas such as bounded iterations, seven-item working memory, resource monitoring and validation gates; those ideas are archaeological evidence, not authority for pub4, and the current constitution already owns the corresponding modern mechanisms.

The archive inventory is broader than the Rails snapshots alone: `BRGEN_OLD.zip`, `brgen_ANCIENT_20240622.tgz`, `arch_20240622.tgz`, `__docs_20240804.tgz`, the 2024 Rails/Amber/brgen vertical tarballs, bsdports snapshots, shell snapshots, and the old framework text files are all present in the source repository.

The GitHub connector can enumerate these binary archive objects but cannot safely decode ZIP/TGZ bytes as UTF-8, so this session did not perform a false "extraction" claim. Their expanded/textual descendants, archive inventory, historical commits, old master configs, prompts, Rails generators and UI notes were cross-checked instead. The existing `MASTER/tools/extract_legacy_archives.zsh` remains the deterministic local extractor when binary bytes are materialized on a machine.

Historical dependencies such as Redis, StimulusReflex, Bootstrap-era cards and framework-specific chrome were not restored. The recovered semantics were carried forward into the current law registry and token system instead.
