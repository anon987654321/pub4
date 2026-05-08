# TRIAD Self-Review Attempt (2026-05-08)

## What I ran

- `bundle exec ruby exe/master orient`
- `ruby exe/master /triad`
- `bundle install`

## Execution outcome

Running TRIAD against MASTER was blocked by dependency bootstrap failures in this environment:

1. `bundle exec ruby exe/master orient` failed because dependencies were not installed (`rb-edge-tts` git source not checked out).
2. `ruby exe/master /triad` failed immediately with `cannot load such file -- zeitwerk`.
3. `bundle install` failed with repeated `403 "Forbidden"` responses while attempting to install the lockfile's bundler version and fetch remote gems.

## Suggestions and improvements

### 1) Add an explicit preflight command for local/self scans

Create a lightweight preflight mode (`/preflight` or `master preflight`) that checks:

- Ruby version compatibility
- Bundler version compatibility with `Gemfile.lock`
- Reachability of remote git gem sources
- Presence of required gems

This would surface actionable setup issues before users invoke `/triad`.

### 2) Add an offline-safe fallback mode for `/triad`

If runtime dependencies cannot be installed, allow `/triad` to run in a reduced mode that still performs:

- Static file graph and architecture checks
- RuboCop/Reek checks if available
- Heuristic self-review from repository files

This would preserve some value in restricted or flaky network environments.

### 3) Improve dependency failure messaging

On startup failures, print a concise remediation section with copy-paste commands, for example:

- `bundle config set --local path vendor/bundle`
- `bundle install`
- optional mirror/proxy instructions when 403s occur

### 4) Vendor or pin high-risk git dependencies

`rb-edge-tts` as a git dependency increases fragility. Consider one of:

- vendoring this dependency
- pinning to a released gem when available
- adding fallback behavior when optional audio dependencies are unavailable

### 5) Commit a reproducible CI/self-check path

Add a CI target that proves `exe/master /triad` can run in a clean environment, and document it in `README`/operator docs. This prevents setup drift.

## Recommended next step

After dependency/network issues are resolved, rerun:

- `bundle exec ruby exe/master orient`
- `bundle exec ruby exe/master` then `/triad`

and append the generated triad output to this report.
