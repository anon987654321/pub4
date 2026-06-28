---
name: MASTER has two Gemfiles
description: MASTER/Gemfile (CLI) and MASTER/web/Gemfile (Falcon web) are independent — adding a gem to one does NOT make it available in the other
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
`MASTER/web/Gemfile` has `gem "master", path: ".."` — loads via gemspec, not parent Gemfile. Gems used in `MASTER/lib/` from web must be in **both** `MASTER/Gemfile` AND `MASTER/web/Gemfile`, or in `master.gemspec` as runtime dep.

Bundling once leaves Falcon unable to `require` — LoadError → controller rescue → 503 (rb-edge-tts: CLI ok, `/chat/tts` failed).

**Apply:** edit both Gemfiles; `bundle install` in `MASTER/` and `MASTER/web/`; verify gem in `MASTER/web/Gemfile.lock`.