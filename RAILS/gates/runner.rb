#!/usr/bin/env ruby
# frozen_string_literal: true

# Consolidated Rails Gates Runner — the one entrypoint for every gate.
#
# Usage:
#   ruby RAILS/gates/runner.rb --all
#   ruby RAILS/gates/runner.rb production domain_alignment
#   ruby RAILS/gates/runner.rb --list
#
# Every gate is declared in gates.yml and nowhere else. Most run in-process via
# a Deploy::* class returning a GateResult; three keep a subprocess because they
# shell out or forward arguments. Composite gates already run their leaves, so
# --all drops a leaf whose composite is also selected.

# Forces Encoding.default_external = UTF_8. Seven of the per-gate scripts this
# runner replaced required it and it was not delegation: under a C locale --
# which is exactly how OPENBSD/integrity_gate.rb invokes them, deliberately --
# Ruby defaults file reads to US-ASCII and every gate that reads UTF-8 source
# or config fails. Dropping it silently broke production, frontend and
# domain_align inside the integrity chain while they passed standalone.
require_relative "../../OPENBSD/lib/utf8"
require "optparse"
require "rbconfig"
require "yaml"

GATES_DIR = __dir__

# Say which interpreter this is before anything runs. The repo pins 3.4.9 in
# .ruby-version while MASTER runs the system Ruby and vm23 runs ruby34 — every
# wrong pairing fails cryptically deep in a gem, so the mismatch is named here
# at the door instead. A warning, not an abort: most gates read source as text
# and run fine anywhere; the ones that boot an app bundle are the ones that die.
pinned = File.read(File.join(File.expand_path("../..", __dir__), ".ruby-version")).strip rescue nil
if pinned && !RUBY_VERSION.start_with?(pinned.sub(/\.\d+\z/, ""))
  warn "[gates] ruby #{RUBY_VERSION}, repo pins #{pinned} — app-bundle gates may fail; use `RBENV_VERSION=#{pinned} rbenv exec ruby gates/runner.rb ...`"
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
RAILS_ROOT = File.expand_path("..", __dir__)
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

# Counts the pass lines interpolate. Lambdas, not values: a gate's own constant
# is only defined once its file has been required, and nothing should pay for a
# directory walk on a run that never prints the message.
COUNTERS = {
  "apps" => -> {
    require_relative "../../OPENBSD/lib/deploy_inventory"
    Deploy::Inventory.new(root: REPO_ROOT).apps.size
  },
  "schemas" => -> { Dir.glob(File.join(REPO_ROOT, "RAILS", "*", "db", "schema.rb")).size },
  "assets" => -> { Deploy::MasterWebAssetsGate::REQUIRED.size },
}.freeze

def counter(name)
  @counters ||= {}
  @counters.fetch(name) { |key| @counters[key] = COUNTERS.fetch(key).call }
end

# "%{apps}" -> 3. Only resolves the counters a message actually names, so a gate
# whose message has no placeholder never triggers an inventory read.
def pass_message(row)
  message = row["pass"].to_s
  message.gsub(/%\{(\w+)\}/) { counter(Regexp.last_match(1)).to_s }
end

def subprocess?(row) = row.key?("script")

def ruby_cmd
  ruby_runner = File.join(REPO_ROOT, "MASTER", "lib", "pub4", "ruby_runner.rb")
  if File.file?(ruby_runner)
    require ruby_runner
    Pub4::RubyRunner.gate_ruby
  else
    ENV.fetch("RUBY_CMD", "ruby").split
  end
end

def resolve_gates(keys)
  keys.reject do |key|
    parent = GATES.dig(key, "covered_by")
    parent && keys.include?(parent)
  end
end

def visual_contract_capture_args
  return [] unless ENV["VISUAL_CAPTURE"] == "1"

  args = %w[--capture]
  args += %w[--app] + [ENV.fetch("VISUAL_CAPTURE_APP", "brgen")]
  args += %w[--base] + [ENV.fetch("VISUAL_CAPTURE_BASE", "http://127.0.0.1:38182")]
  args
end

def gate_extra_args(key)
  key == "visual_contract" ? visual_contract_capture_args : []
end

# ENV name -> keyword argument. Only "1" enables one, matching what the old
# per-gate entrypoints did with GATE_SKIP_NESTED.
def run_kwargs(row)
  row.fetch("env_flags", {}).each_with_object({}) do |(var, keyword), kwargs|
    kwargs[keyword.to_sym] = true if ENV[var] == "1"
  end
end

def run_in_process(key, row, verbose:)
  require_relative row.fetch("require")
  klass = Object.const_get(row.fetch("class"))
  kwargs = run_kwargs(row)
  result = kwargs.empty? ? klass.run : klass.run(**kwargs)
  emit_gate_result(key, result, verbose:)
# Fail-open, per arXiv 2607.07405: a gate that raises records the error and
# allows the call rather than inventing a block. Everything is caught, not just
# StandardError — the crashes this actually sees are LoadError from a moved
# `require` and NameError from a renamed class, both of which are ScriptError
# or StandardError but neither of which a bare `rescue` would have caught.
#
# Before this, one raising gate ended the process: `outcomes` is built by a
# single `to_h` over every gate, so the exception escaped the loop and the
# forty-six gates after it in --all order never ran, with a backtrace in place
# of the summary. That is not a strict suite, it is an unread one.
rescue StandardError, ScriptError => e
  require_relative "../../OPENBSD/lib/gate_result"
  emit_gate_result(key, Deploy::GateResult.from_error(e, gate: key), verbose:)
end

def emit_gate_result(key, result, verbose:)
  unless result.respond_to?(:render)
    warn "[gates] #{key}: in-process gate did not return Deploy::GateResult"
    return :failed
  end

  # Kept for the ledger, which wants the finding counts and not just the verdict:
  # a gate that failed with one finding and one that failed with ninety read the
  # same in the outcome column.
  @last_result = result

  autofix_off = ENV["GATE_AUTOFIX"].to_s.strip.downcase.match?(/\A(0|false|no|off)\z/)
  warn "[gates] GATE_AUTOFIX #{autofix_off ? 'off (report-only)' : 'on (fix + remeasure)'}"

  # GateResult owns both the rendering and the three-way classification. A gate
  # that could not run its check is not a pass: it does not block the suite (off
  # the deploy host most rendered gates genuinely cannot run), but it must not be
  # counted in the "ALL PASSED" line either. run_one prints the outcome label.
  #
  # The gate's own pass line only prints when it was asked for by name, which is
  # how it is invoked directly. Under --all the suite summary speaks for
  # it, and forty success lines would bury the failures.
  verbose ? result.render(pass_message(GATES.fetch(key))) : result.render
end

def run_subprocess(key, row)
  path = File.join(GATES_DIR, row.fetch("script"))
  unless File.file?(path)
    warn "[gates] Missing gate script for #{key}: #{path}"
    return :failed
  end
  extra = gate_extra_args(key)
  puts "[gates] visual_contract capture enabled (VISUAL_CAPTURE=1)" if key == "visual_contract" && extra.include?("--capture")
  ok = system(*ruby_cmd, path, *extra)
  status = $?

  # Three cases, and two of them are easy to conflate.
  #
  # `system` returns nil when the command could not be run at all — no such
  # interpreter, script not executable. That is the gate erroring, not the gate
  # failing, and reporting it as FAILED is the false block arXiv 2607.07405
  # measures. Same for a signal death: SIGKILL is the OOM killer or a timeout,
  # never a verdict about the tree.
  #
  # Exit 1 stays :failed. Ruby exits 1 both for `report!`'s deliberate block and
  # for an uncaught exception, so the two are genuinely indistinguishable from
  # out here; the in-process path above is where a crash gets named, and that is
  # the path 44 of the 47 gates take.
  return :errored if ok.nil?
  return :errored if status.respond_to?(:signaled?) && status.signaled?

  # Exit 3 is "I could not measure", the state the in-process gates express with
  # GateResult#inconclusive! and the runner already counts and prints apart from
  # passes. A subprocess can only speak in exit codes, so it gets one.
  #
  # Without it these three gates reported a clean pass whenever their
  # preconditions were missing — and for visual_contract the precondition is
  # Chrome plus a booted app, which is exactly the situation where "no pixels
  # differed" is true because no pixels were compared. 44 of 47 gates run
  # in-process and never had this hole; these are the three that did.
  return :inconclusive if status.exitstatus == SUBPROCESS_INCONCLUSIVE

  status.success? ? :passed : :failed
end

OUTCOME_LABEL = {
  passed: "PASSED",
  failed: "FAILED",
  inconclusive: "INCONCLUSIVE (checked nothing)",
  errored: "ERRORED (gate broke, blocked nothing)",
}.freeze

def ledger
  @ledger ||= begin
    require_relative "../../OPENBSD/lib/gate_ledger"
    Deploy::GateLedger.new
  end
end

def run_one(key, verbose:)
  row = GATES.fetch(key)
  source = subprocess?(row) ? row["script"] : row["class"]
  puts "\n==> [gates] Running #{key} (#{source})"
  @last_result = nil
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  outcome = subprocess?(row) ? run_subprocess(key, row) : run_in_process(key, row, verbose:)
  elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  puts "[gates] #{key} #{OUTCOME_LABEL.fetch(outcome)}"
  ledger.record(
    gate: key,
    outcome: outcome,
    run_id: RUN_ID,
    failures: @last_result.respond_to?(:failures) ? @last_result.failures.size : 0,
    warnings: @last_result.respond_to?(:warnings) ? @last_result.warnings.size : 0,
    errors: @last_result.respond_to?(:errors) ? @last_result.errors.size : 0,
    duration_ms: elapsed
  )
  outcome
end

def list_gates
  puts "Available gates (use the short name with runner.rb):"
  GATES.each do |name, row|
    kind = subprocess?(row) ? "subprocess #{row['script']}" : row["class"]
    puts "  #{name.ljust(22)} #{kind}"
  end
  puts
  puts "Composite gates (their leaves are skipped when the parent is also selected):"
  GATES.group_by { |_, row| row["covered_by"] }.each do |parent, rows|
    next unless parent

    puts "  #{parent} includes: #{rows.map(&:first).join(', ')}"
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby RAILS/gates/runner.rb [options] [gate_names...]"
  opts.on("--all", "Run all registered gates") { options[:all] = true }
  opts.on("--list", "List available gates") { options[:list] = true }
  opts.on("--ledger", "Report each gate's outcome history (fire rate, error rate)") { options[:ledger] = true }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

if options[:list]
  list_gates
  exit
end

if options[:ledger]
  ledger.render
  exit
end

unknown = ARGV.reject { |name| GATES.key?(name) }
if unknown.any?
  warn "[gates] unknown gate(s): #{unknown.join(', ')}. Use --list."
  exit 1
end

requested = options[:all] || ARGV.empty? ? GATES.keys : ARGV

gates_to_run = resolve_gates(requested)
skipped = requested - gates_to_run
puts "[gates] Skipping #{skipped.join(', ')} (covered by composite gates in this run)" if skipped.any?

# One named gate is the direct-invocation case the per-gate scripts used to
# serve, so let it print its own success line.
verbose = gates_to_run.size == 1
total = gates_to_run.size
outcomes = {}
gates_to_run.each_with_index do |key, index|
  puts "[gates] #{index + 1}/#{total} #{key}" unless verbose
  outcomes[key] = run_one(key, verbose:)
end

failed = outcomes.select { |_, o| o == :failed }.keys
unchecked = outcomes.select { |_, o| o == :inconclusive }.keys
errored = outcomes.select { |_, o| o == :errored }.keys
passed = outcomes.count { |_, o| o == :passed }

puts "\n#{'=' * 50}"

# Whether the browser-backed half of this run measured anything.
#
# Those gates degrade to a warning without Chrome rather than failing, which
# is right — a missing browser is a property of the machine, not a verdict
# about the tree — but it means a green `--all` says nothing about them unless
# you separately know Chrome was there. The committed visual manifests are the
# argument for saying it out loud: eighteen declared states, three actual
# pages, and every summary printed above them read PASSED.
#
# One line, printed with the verdict. It never changes an exit code.
BROWSER_BACKED = %w[
  rendered_suite rendered_invariants rendered_geometry webgl_surfaces viewport_spill
  layout_snapshot journey_invariant reflow keyboard_flow mobile_flow cross_app
  occlusion page_simulation visual_contract
].freeze

browser_gates = gates_to_run & BROWSER_BACKED
if browser_gates.any?
  chrome = begin
    require_relative "support/cdp_session"
    Deploy::CdpSession.available?
  rescue StandardError
    false
  end
  if chrome
    puts "[gates] browser: Chrome present — #{browser_gates.size} browser-backed gate(s) could measure"
  else
    puts "[gates] browser: NO Chrome — #{browser_gates.size} browser-backed gate(s) degraded to " \
         "warnings and measured nothing (#{browser_gates.join(', ')})"
  end
end

# Printed before the verdict and independently of it, because it is the one line
# that changes what the rest of the summary means. An errored gate blocked
# nothing (fail-open), so a run can say ALL PASSED while a gate that would have
# caught the regression never ran — and unlike a failure, nobody goes looking
# for it. GATE_STRICT_ERRORS=1 turns these into failures on the deploy host.
if errored.any?
  puts "[gates] #{errored.size} gate(s) ERRORED and blocked nothing: #{errored.join(', ')}"
  puts "[gates]   whatever those guard was not checked this run " \
       "(GATE_STRICT_ERRORS=1 to fail on it; --ledger for how long this has been true)"
end

if failed.any?
  puts "[gates] SOME GATES FAILED: #{failed.join(', ')}"
elsif unchecked.any?
  # Never claim a coverage number the run did not earn. This line is the whole
  # point of the third state: "ALL PASSED (24)" used to include gates that had
  # no Chrome, no listening app and nothing to measure.
  puts "[gates] #{passed} gate(s) passed, #{unchecked.size} inconclusive: #{unchecked.join(', ')}"
elsif errored.any?
  # Same rule as the inconclusive line above, for the same reason: "ALL SELECTED
  # GATES PASSED (46)" over a run where the forty-seventh crashed is a coverage
  # number the run did not earn, and it is the number people quote.
  puts "[gates] #{passed} gate(s) passed, #{errored.size} errored: #{errored.join(', ')}"
else
  puts "[gates] ALL SELECTED GATES PASSED (#{passed})"
end
exit failed.any? ? 1 : 0
