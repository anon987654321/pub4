#!/usr/bin/env ruby
# frozen_string_literal: true

# Consolidated repository Gates Runner — the one entrypoint for every gate.
#
# Usage:
#   ruby MASTER/gates/runner.rb --all
#   ruby MASTER/gates/runner.rb production domain_alignment
#   ruby MASTER/gates/runner.rb --list
#   ruby MASTER/gates/runner.rb --explain
#
# Every Rails probe is declared in gates.yml and nowhere else. MASTER owns
# orchestration and completion policy; this file is the Rails probe registry
# and compatibility adapter for callers that still invoke it directly. Most run in-process via
# a Deploy::* class returning a GateResult; three keep a subprocess because they
# shell out or forward arguments. Composite gates already run their leaves, so
# --all drops a leaf whose composite is also selected.
#
# A new gate ships with a fixture it must flag and one it must not, because a
# gate never run against a known-bad input is a claim, not an instrument;
# tap_target_probe and focus_walk_probe are the shape. An existing gate gains its
# pair when it is next touched.

# Forces Encoding.default_external = UTF_8. Seven of the per-gate scripts this
# runner replaced required it and it was not delegation: under a C locale --
# which is exactly how OPENBSD/gates/integrity_gate.rb invokes them, deliberately --
# Ruby defaults file reads to US-ASCII and every gate that reads UTF-8 source
# or config fails. Dropping it silently broke production, frontend and
# domain_align inside the integrity chain while they passed standalone.
require_relative "../../OPENBSD/lib/utf8"
require_relative "../lib/trace/dmesg"
require_relative "../lib/operator/strict_mode"
require "optparse"
require "rbconfig"
require "tempfile"
require "yaml"

GATES_DIR = __dir__

# MASTER_STRICT is the public mode; these existing flags are its execution form.
# Direct callers without a mode retain today's contribute behaviour.
if ENV.key?("MASTER_STRICT")
  Operator::StrictMode.flags.each { |name, value| ENV[name] = value }
end

# Say which interpreter this is before anything runs. The repo pins the exact
# version in .ruby-version; running a different interpreter makes a later gem
# failure cryptic, so the mismatch is rejected at the boundary. Abort, not a warning: a
# warning next to a later gem crash reads as two findings, and operators
# learned to ignore the first.
pinned = File.read(File.join(File.expand_path("../..", __dir__), ".ruby-version")).strip rescue nil
if pinned && RUBY_VERSION != pinned
  abort "[gates] ruby #{RUBY_VERSION}, repo pins #{pinned} — use `RBENV_VERSION=#{pinned} rbenv exec ruby gates/runner.rb ...`"
end

# The exit code a subprocessed gate uses for "preconditions missing, nothing
# measured". Not 0, which claims a clean run, and not 1, which claims a verdict
# about the tree.
#
# visual_contract.rb is the only one of the three subprocess gates that uses it,
# and deliberately so. release.rb and rails_runtime.rb each always run a static
# half — eight contract tests and four gate classes, a source scan — and only
# their live halves can be skipped, which is a partial rather than a blind run.
# They already list what they skipped, and GATE_STRICT_INCONCLUSIVE makes that
# blocking. visual_contract without Chrome measures nothing at all.
SUBPROCESS_INCONCLUSIVE = 3
RAILS_ROOT = File.join(REPO_ROOT, "RAILS")
REPO_ROOT = File.expand_path("../..", __dir__)

# GATES_FILE points the runner at a different registry. It exists so the
# fail-open behaviour below can be proved end-to-end: a gate that raises has to
# actually be run through this file to show that the run survives it, and there
# is deliberately no such gate in gates.yml.
GATES = YAML.safe_load_file(ENV.fetch("GATES_FILE", File.join(GATES_DIR, "gates.yml"))).freeze

# Groups every gate of one invocation into one row in the ledger, so "this gate
# failed" can be told apart from "this whole run failed". The pid disambiguates
# two runs started in the same second, which happens in CI.
RUN_ID = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{Process.pid}"

# Every line the runner itself prints reads `gates0 at <parent>: <fact>`. A
# deploy sets PUB4_DEPLOY_APP, so its gate lines name the app being deployed.
GATE_UNIT = "gates0"
GATE_PARENT = ENV.fetch("PUB4_DEPLOY_APP", "rails")

def say(detail)
  clear_progress
  puts Master::Trace::Dmesg.line(GATE_UNIT, GATE_PARENT, detail)
end

# Gates use the same append-only dmesg stream as the rest of pub4.
# A gate never repaints a terminal line: scrollback is the record.
def progress(detail)
  say(detail)
end

def clear_progress