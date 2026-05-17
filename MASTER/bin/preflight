#!/usr/bin/env zsh
# MASTER preflight check — run before deploying to OpenBSD
set -euo pipefail
setopt err_exit

ROOT=${${0:A}:h:h}
cd "$ROOT"

print "MASTER preflight — ${ROOT}"

# Ruby version
[[ -x $(whence ruby) ]] || { print "FAIL: ruby not found"; exit 1 }
print "ok: ruby $(ruby -e 'print RUBY_VERSION')"

# Bundler
[[ -x $(whence bundle) ]] || { print "FAIL: bundler not found"; exit 1 }
print "ok: bundler $(bundle -v)"

# Gem dependencies
bundle check >/dev/null 2>&1 || { print "FAIL: bundle check failed (run: bundle install)"; exit 1 }
print "ok: gems installed"

# API keys
[[ -n "${REPLICATE_API_KEY:-}" ]]   && print "ok: REPLICATE_API_KEY" || print "warn: REPLICATE_API_KEY not set"
[[ -n "${ANTHROPIC_API_KEY:-}" ]]   && print "ok: ANTHROPIC_API_KEY" || print "warn: ANTHROPIC_API_KEY not set"
[[ -n "${OPENROUTER_API_KEY:-}" ]]  && print "ok: OPENROUTER_API_KEY" || print "warn: OPENROUTER_API_KEY not set"

# Syntax
print "check: ruby syntax"
ruby -c lib/master.rb >/dev/null
print "ok: lib/master.rb syntax"

# Tests
print "check: test suite"
bundle exec ruby -Itest test/test_result.rb test/test_ring_buffer.rb test/test_axioms.rb test/test_prune.rb 2>&1 | tail -1
print "ok: tests passed"

print "\nMASTER preflight complete."
