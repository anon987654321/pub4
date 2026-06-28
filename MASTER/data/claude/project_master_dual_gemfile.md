---
name: MASTER has two Gemfiles
description: MASTER/Gemfile (CLI) and MASTER/web/Gemfile (Falcon web) are independent — adding a gem to one does NOT make it available in the other
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---

`MASTER/Gemfile` serves the CLI and `MASTER/web/Gemfile` serves the Falcon web tier. They are independent—adding a gem to one does not make it available in the other.

`MASTER/web/Gemfile` declares `gem "master", path: ".."`, which loads via the gemspec, not the parent Gemfile. Gems used in `MASTER/lib/` from web handlers must appear in both `MASTER/Gemfile` and `MASTER/web/Gemfile`, or in `master.gemspec` as a runtime dependency. Bundling only once leaves Falcon unable to `require` the gem—a LoadError that surfaces as a controller rescue and 503. `rb-edge-tts` exhibited this: CLI worked while `/chat/tts` failed.

When adding a dependency, edit both Gemfiles, run `bundle install` in `MASTER/` and `MASTER/web/`, and verify the gem appears in `MASTER/web/Gemfile.lock`.