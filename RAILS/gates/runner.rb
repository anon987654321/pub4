#!/usr/bin/env ruby
# frozen_string_literal: true

# Consolidated Rails Gates Runner — the one entrypoint for every gate.
#
# Usage:
#   ruby RAILS/gates/runner.rb --all
#   ruby RAILS/gates/runner.rb production domain_alignment
#   ruby RAILS/gates/runner.rb --list
#   ruby RAILS/gates/runner.rb --explain
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
require_relative "../shared/lib/operator/dmesg"
require "optparse"
require "rbconfig"
require "tempfile"
require "yaml"

GATES_DIR = __dir__

# Say which interpreter this is before anything runs. The repo pins 3.4.9 in
# .ruby-version while MASTER runs the system Ruby and vm23 runs ruby34 — every
# wrong pairing fails cryptically deep in a gem. Abort, not a warning: a
# warning next to a later gem crash reads as two findings, and operators
# learned to ignore the first.
pinned = File.read(File.join(File.expand_path("../..", __dir__), ".ruby-version")).strip rescue nil
if pinned && !RUBY_VERSION.start_with?(pinned.sub(/\.\d+\z/, ""))
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

# Every line the runner itself prints reads `gates0 at <parent>: <fact>`. A
# deploy sets PUB4_DEPLOY_APP, so its gate lines name the app being deployed.
GATE_UNIT = "gates0"
GATE_PARENT = ENV.fetch("PUB4_DEPLOY_APP", "rails")

def say(detail)
  clear_progress
  puts Operator::Dmesg.line(GATE_UNIT, GATE_PARENT, detail)
end

# Gates use the same append-only dmesg stream as the rest of pub4.
# A gate never repaints a terminal line: scrollback is the record.
def progress(detail)
  say(detail)
end

def clear_progress
  nil
end

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
  ruby_runner = File.join(REPO_ROOT, "MASTER", "lib", "operator", "ruby_runner.rb")
  if File.file?(ruby_runner)
    require ruby_runner
    Operator::RubyRunner.gate_ruby
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

def needs(key) = Array(GATES.dig(key, "needs"))

# What this run is about to spend, before it spends it.
#
# runner.rb printed nothing before starting, and two of these gates are measured
# in tens of minutes: constitutional_scan at 48 minutes on brgen alone inside a
# model round trip, rendered_suite monopolising a Mac for an hour. So a person
# who typed --all found out what it cost by waiting.
#
# The number is the ledger's own median for that gate on THIS machine, not a
# figure declared in gates.yml. A declared cost is a fifth hand-maintained table
# and, worse, it cannot show the failure it is for: a gate that doubles reads the
# same as a gate that did not. A median over real runs moves when the gate does.
#
# One line, and only for a run long enough to be worth deciding about. A
# deploy's nine gates take forty seconds and need no forecast; --all locally
# takes tens of minutes and does. The per-gate medians are `--ledger`'s rows.
PLAN_WORTH_SAYING_S = 60

def plan_for(keys)
  history = ledger.entries.group_by { |row| row["gate"] }
  medians = keys.map do |key|
    times = history.fetch(key, []).filter_map { |row| row["duration_ms"] }.sort
    times.empty? ? nil : times[times.size / 2]
  end
  known_ms = medians.compact.sum
  return if known_ms < PLAN_WORTH_SAYING_S * 1000

  unmeasured = medians.count(&:nil?)
  say("#{keys.size} gates planned, ~#{duration(known_ms)} measured here" \
      "#{unmeasured.zero? ? '' : ", #{unmeasured} unmeasured"} (--ledger per gate)")
end

def duration(ms)
  seconds = ms.to_f / 1000
  return format("%.1fs", seconds) if seconds < 90

  format("%dm%02ds", (seconds / 60).floor, (seconds % 60).round)
end

# Chrome, named from the registry's `needs` rather than from a list in this file.
# A browser gate without Chrome degrades to a warning rather than failing, which
# is right — a missing browser is a property of the machine, not a verdict about
# the tree — but it means a green run says nothing about them unless you
# separately know Chrome was there. The committed visual manifests are the
# argument for saying it out loud: eighteen declared states, three actual pages,
# and every summary printed above them read PASSED.
#
# Missing Chrome is an explicit inconclusive outcome. A present Chrome is the
# normal case: a browser gate that ran has its own measured outcome to report.
def report_browser_precondition(keys)
  wanted = keys.select { |key| needs(key).include?("browser") }
  return [] if wanted.empty?

  chrome = begin
    require_relative "support/cdp_session"
    Deploy::CdpSession.available?
  rescue StandardError => e
    say("CDP unavailable (#{e.class}: #{e.message.lines.first.to_s.strip})")
    false
  end
  return [] if chrome

  say("no Chrome, so #{wanted.size} browser gates measured nothing: #{wanted.join(', ')}")
  wanted
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

# A require that names a tree is resolved from the repo root; everything else
# is relative to this file, as it always was.
#
# Six gates moved out on 2026-09-11 because they never belonged here: two check
# MASTER's own face and one runs MASTER's scan chain, and three check the box —
# DNS zones, domain alignment, the port inventory. A gate lives with the thing
# it measures, and RAILS/gates is for the gates that only mean something with
# the apps running. The row stays here either way: one registry, one
# declaration per gate.
def require_gate(path)
  return require File.join(REPO_ROOT, path) if path.start_with?("MASTER/", "OPENBSD/", "MASTER/tools/")

  require_relative path
end

def run_in_process(key, row, verbose:)
  require_gate(row.fetch("require"))
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
    warn "#{key}: in-process gate did not return Deploy::GateResult"
    return :failed
  end

  # Kept for the ledger, which wants the finding counts and not just the verdict:
  # a gate that failed with one finding and one that failed with ninety read the
  # same in the outcome column.
  @last_result = result

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
    warn "missing gate script for #{key}: #{path}"
    return :failed
  end
  extra = gate_extra_args(key)
  puts "visual_contract capture enabled (VISUAL_CAPTURE=1)" if key == "visual_contract" && extra.include?("--capture")
  # $stdout and $stderr are the run's capture file here, so the child writes
  # into the same record an in-process gate's puts and warn do.
  ok = system(*ruby_cmd, path, *extra, out: $stdout, err: $stderr)
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
  passed: "passed",
  failed: "failed",
  inconclusive: "inconclusive, checked nothing",
  errored: "errored, blocked nothing",
}.freeze

def ledger
  @ledger ||= begin
    require_relative "../../OPENBSD/lib/gate_ledger"
    Deploy::GateLedger.new
  end
end

# A passing gate's output, when it is not the one gate asked for, goes to a log
# beside the ledger: a run that points the ledger at a scratch directory keeps
# it there too, and the ledger already holds each gate's outcome and time. With
# the ledger off, or a log that will not open, the output prints instead, so
# retired detail reaches a file or the reader and never neither.
OUTPUT_LOG_MAX_BYTES = 4_000_000

def output_log
  return @output_log if defined?(@output_log)

  path = File.join(File.dirname(ledger.path), ".gate_output.log")
  @output_log = ledger.enabled? ? File.open(path, File.size?(path).to_i > OUTPUT_LOG_MAX_BYTES ? "w" : "a") : nil
rescue SystemCallError
  @output_log = nil
end

# Everything a gate prints, in-process or as a child, into one file, read back
# once it is done. `system` in run_subprocess hands the child these same two.
def capture_output
  saved = [$stdout, $stderr]
  Tempfile.create("gate-output") do |file|
    file.sync = true
    $stdout = $stderr = file
    outcome = yield
    $stdout, $stderr = saved
    file.rewind
    [outcome, file.read.scrub]
  ensure
    $stdout, $stderr = saved
  end
end

def report_gate(key, outcome, lines, seconds, verbose:)
  fact = "#{key} #{OUTCOME_LABEL.fetch(outcome)} in #{Operator::Dmesg.duration(seconds)}"
  if outcome == :passed && !verbose && output_log
    output_log.puts(Operator::Dmesg.line(GATE_UNIT, GATE_PARENT, fact), *lines)
    return
  end
  say(fact) unless outcome == :passed && verbose
  clear_progress
  lines.each { |line| puts line }
end

# Why a gate could not measure, kept for the summary rather than only printed
# under the gate that said it. A full run prints hundreds of lines above its
# verdict, so naming the inconclusive gates at the bottom without their reasons
# tells the reader which gates to scroll back to — one step short of telling
# them what to do about it.
#
# A subprocess gate has no result object to read and can only speak in exit
# codes, so it contributes the code and nothing else. Say that rather than
# leaving a blank line under its name.
@reasons = {}

# A gate that failed while naming no finding is the shape rails_runtime wore for
# months: red every run with an empty failure list, because it broke at require
# time and never reached a check. The reader should not have to guess whether
# the list is empty because nothing was found or because nothing ran.
#
# In-process gates only. A subprocess gate returns an exit code and prints its
# own findings, so the runner holds no result to count — release names a failing
# MASTER contract test on its own stdout and would otherwise be reported here as
# naming nothing, which is the false positive this line exists to avoid.
@empty_failures = []

def record_reasons(key, outcome)
  result = @last_result
  case outcome
  when :inconclusive
    reasons = result.respond_to?(:unchecked) ? Array(result.unchecked) : []
    reasons = ["exit #{SUBPROCESS_INCONCLUSIVE}, no reason given (subprocess gate)"] if reasons.empty?
    @reasons[key] = reasons
  when :failed
    @empty_failures << key if result.respond_to?(:failures) && result.failures.empty?
  end
end

def run_one(key, verbose:)
  row = GATES.fetch(key)
  progress("running #{key}")
  @last_result = nil
  started = clock
  outcome, output = capture_output { subprocess?(row) ? run_subprocess(key, row) : run_in_process(key, row, verbose:) }
  elapsed = ((clock - started) * 1000).round
  lines = Operator::Dmesg.collapse(Operator::Dmesg.plain(output).lines)
  report_gate(key, outcome, lines, elapsed / 1000.0, verbose:)
  record_reasons(key, outcome)
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

require_relative "support/runner_explain"

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby RAILS/gates/runner.rb [options] [gate_names...]"
  opts.on("--all", "Run all registered gates") { options[:all] = true }
  opts.on("--list", "List available gates") { options[:list] = true }
  opts.on("--explain", "Explain each gate and the environment switches, running nothing") { options[:explain] = true }
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

if options[:explain]
  explain_gates
  exit
end

if options[:ledger]
  ledger.render
  exit
end

unknown = ARGV.reject { |name| GATES.key?(name) }
if unknown.any?
  warn "unknown gate(s): #{unknown.join(', ')}. Use --list."
  exit 1
end

requested = options[:all] || ARGV.empty? ? GATES.keys : ARGV

gates_to_run = resolve_gates(requested)
covered = requested - gates_to_run

plan_for(gates_to_run)

# One named gate is the direct-invocation case the per-gate scripts used to
# serve, so let it print its own success line.
verbose = gates_to_run.size == 1
run_started = clock
outcomes = gates_to_run.to_h { |key| [key, run_one(key, verbose:)] }
by_outcome = outcomes.keys.group_by { |key| outcomes[key] }
failed = by_outcome.fetch(:failed, [])
errored = by_outcome.fetch(:errored, [])

# Whether the browser-backed half of this run measured anything.
#
# Those gates degrade to a warning without Chrome rather than failing, which
# is right — a missing browser is a property of the machine, not a verdict
# about the tree — but it means a green `--all` says nothing about them unless
# you separately know Chrome was there. The committed visual manifests are the
# argument for saying it out loud: eighteen declared states, three actual
# pages, and every summary printed above them read passed.
browser_inconclusive = report_browser_precondition(gates_to_run)
browser_inconclusive.each { |key| outcomes[key] = :inconclusive }
by_outcome = outcomes.keys.group_by { |key| outcomes[key] }
failed = by_outcome.fetch(:failed, [])
errored = by_outcome.fetch(:errored, [])

# Printed before the verdict and independently of it, because it is the one line
# that changes what the rest of the summary means. An errored gate blocked
# nothing (fail-open), so a run can read passed while a gate that would have
# caught the regression never ran — and unlike a failure, nobody goes looking
# for it. GATE_STRICT_ERRORS=1 turns these into failures on the deploy host.
if errored.any?
  say("#{errored.join(', ')} errored and blocked nothing; what they guard went unchecked " \
      "(GATE_STRICT_ERRORS=1 fails on it, --ledger says for how long)")
end

# Most gates already open the reason with their own name, and printing it twice
# reads like two gates.
@reasons.each do |key, reasons|
  reasons.each { |reason| say("#{key} measured nothing: #{reason.to_s.delete_prefix("#{key}: ")}") }
end
unless @reasons.empty?
  say("GATE_STRICT_INCONCLUSIVE=1 fails on these; RAILS/bin/triangle up satisfies a live precondition, " \
      "not a deploy-host one")
end

if @empty_failures.any?
  say("#{@empty_failures.join(', ')} failed naming no finding, so broke before a check; run each alone")
end

# The verdict. Never a coverage number the run did not earn: an inconclusive or
# errored gate is named beside the pass count, never folded into it, because
# this is the line people quote.
autofix = ENV["GATE_AUTOFIX"].to_s.strip.downcase.match?(/\A(0|false|no|off)\z/) ? "off" : "on"
verdict = ["#{by_outcome.fetch(:passed, []).size} of #{outcomes.size} passed in " \
           "#{Operator::Dmesg.duration(clock - run_started)}, autofix #{autofix}"]
%i[failed errored inconclusive].each do |outcome|
  verdict << "#{by_outcome[outcome].join(', ')} #{outcome}" if by_outcome[outcome]
end
verdict << "#{covered.size} covered by composites" unless covered.empty?
say(verdict.join("; "))
exit(failed.any? ? 1 : (by_outcome.fetch(:inconclusive, []).any? ? 3 : 0))
