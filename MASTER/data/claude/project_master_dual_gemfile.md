---
name: MASTER has two Gemfiles
description: MASTER/Gemfile (CLI) and MASTER/web/Gemfile (Falcon web) are independent — adding a gem to one does NOT make it available in the other
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
`MASTER/web/Gemfile` declares `gem "master", path: ".."` which loads master via gemspec, NOT via the parent Gemfile. Runtime gems used inside `MASTER/lib/` from the web process must be declared in BOTH `MASTER/Gemfile` AND `MASTER/web/Gemfile`, or in `master.gemspec` as a runtime dep.

**Why:** Bundling them once in MASTER/Gemfile leaves the falcon process unable to require the gem at runtime — the request handler raises LoadError silently and the controller's rescue returns 503. This burned an hour debugging rb-edge-tts that worked in CLI but failed in /chat/tts.

**How to apply:** When adding a gem touched by lib/master/* code that the web app calls, edit both Gemfiles. Run `bundle install` in both `MASTER/` and `MASTER/web/`. Verify by reading `MASTER/web/Gemfile.lock` for the gem name.
