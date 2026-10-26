#!/usr/bin/env ruby
# frozen_string_literal: true

# One check runner for MASTER, RAILS and OPENBSD.
# checks/checks.yml is the declaration surface; this file only executes it.

require "json"
require "open3"
require "optparse"
require "rbconfig"
require "yaml"

# The box runs with a US-ASCII locale; source files are UTF-8, and two checks raised
# "invalid byte sequence" reading them there and blocked nothing.
Encoding.default_external = Encoding::UTF_8

ROOT = File.expand_path("../..", __dir__)
CHECKS_DIR = __dir__
REGISTRY_DEFAULT = File.join(CHECKS_DIR, "checks.yml")
CHECK_UNIT = "checks0"
CHECK_PARENT = ENV.fetch("PUB4_DEPLOY_APP", "rails")
SUBPROCESS_INCONCLUSIVE = 3

$LOAD_PATH.unshift(ROOT, CHECKS_DIR)
require File.join(ROOT, "MASTER", "checks", "support", "check_autofix")
require File.join(ROOT, "MASTER", "checks", "support", "check_result")
require File.join(ROOT, "MASTER", "lib", "execution", "contract")
require File.join(ROOT, "MASTER", "checks", "support", "check_ledger")
require File.join(ROOT, "MASTER", "checks", "support", "flow_coverage")
require File.join(ROOT, "MASTER", "checks", "support", "token_reads")
require File.join(ROOT, "MASTER", "lib", "trace", "dmesg")
require File.join(ROOT, "MASTER", "lib", "gap")

CHECKS_FILE = ENV.fetch("CHECKS_FILE", REGISTRY_DEFAULT)
CHECKS = YAML.safe_load_file(CHECKS_FILE).freeze
unless CHECKS.is_a?(Hash)
  abort "checks: invalid registry root (expected a mapping)"
end

# A row that cannot identify an executable was historically recorded as
# :errored during a run and could still leave exit status zero by default.
# This is a declaration error, so refuse the registry before running any checks.
invalid_registry_rows = CHECKS.filter_map do |name, row|
  if !row.is_a?(Hash)
    "#{name} must declare a mapping"
  elsif row["class"].to_s.strip.empty? && row["script"].to_s.strip.empty?
    "#{name} must declare class: or script:"
  end
end
abort "checks: invalid registry: #{invalid_registry_rows.join("; ")}" unless invalid_registry_rows.empty?

LEDGER = Deploy::CheckLedger.new
RUN_ID = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{Process.pid}"

def say(detail)
  puts Master::Trace::Dmesg.line(CHECK_UNIT, CHECK_PARENT, detail)
rescue StandardError
  puts "#{CHECK_UNIT} at #{CHECK_PARENT}: #{detail}"
end

# The check in hand, for whoever is waiting on this process with its output
# captured (Operator::CheckHeartbeat reads it on a timer).
def note_progress(index, total, name)
  path = ENV["CHECK_PROGRESS_FILE"].to_s
  return if path.empty?

  File.write(path, JSON.generate("n" => index, "total" => total, "name" => name, "at" => Time.now.to_f))
rescue SystemCallError
  nil
end

def log_retired(line)
  path = File.join(File.dirname(LEDGER.path), ".check_output.log")
  File.open(path, "a") { |io| io.puts(line) }
rescue StandardError
  nil
end

def registry
  CHECKS
end

def selected_names(all:, requested:)
  names = requested.empty? ? registry.keys : requested
  names = registry.keys if all
  unknown = names.reject { |name| registry.key?(name) }
  abort "checks: unknown check(s): #{unknown.join(", ")}" unless unknown.empty?
  return names unless all

  names.reject { |name| registry.fetch(name).is_a?(Hash) && registry.fetch(name)["covered_by"] }
end

def constant_for(name)
  name.split("::").inject(Object) { |owner, part| owner.const_get(part, false) }
end

def require_check(row)
  path = row["require"].to_s
  return if path.empty?

  absolute = if path.start_with?("MASTER/", "OPENBSD/")
               File.join(ROOT, path)
             else
               File.join(CHECKS_DIR, path)
             end
  require absolute
end

# Asks the same question the probes ask, so a Mac with Chrome in /Applications is not reported
# as having no browser: the PATH-only check made every browser check inconclusive there.
def browser_available?
  require File.join(CHECKS_DIR, "support", "cdp_session")

  Deploy::CdpSession.available?
rescue LoadError, StandardError
  %w[google-chrome chromium chromium-browser].any? do |command|
    system("command", "-v", command, out: File::NULL, err: File::NULL)
  end
end

def precondition_result(name, row)
  needs = Array(row["needs"]).map(&:to_s)
  return unless needs.include?("browser")
  return if browser_available?

  Deploy::CheckResult.new.inconclusive!("#{name}: browser/Chromium unavailable", gap: Master::Gap::NO_BROWSER)
end

# A script check cannot hand a Gap through its exit code, so checks.yml declares
# the one its exit 3 means (gap: {horizon:, cost_to_check:, decidability:}).
def declared_gap(row)
  spec = row["gap"]
  spec && Master::Gap.new(**spec.to_h { |key, value| [key.to_sym, value.is_a?(String) ? value.to_sym : value] })
end

def run_script(path, args, gap: nil)
  command = [RbConfig.ruby, path, *args]
  stdout, status = Open3.capture2e(ENV.to_h, *command, chdir: ROOT)
  stdout.to_s.lines.each { |line| log_retired(line.chomp) }
  result = Deploy::CheckResult.new

  if status.exitstatus == SUBPROCESS_INCONCLUSIVE
    result.inconclusive!("#{File.basename(path)}: subprocess measured nothing", gap:)
  elsif status.success?
    result.checked!
  else
    result.fail("#{File.basename(path)} exited #{status.exitstatus}")
  end

  [result, stdout]
rescue StandardError => e
  [Deploy::CheckResult.from_error(e, check: File.basename(path)), ""]
end

def run_check(name, row, args)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = precondition_result(name, row)
  output = +""

  if result.nil?
    begin
      require_check(row)
      if row["script"]
        path = File.join(CHECKS_DIR, row["script"].to_s)
        result, output = run_script(path, args, gap: declared_gap(row))
      else
        klass = constant_for(row.fetch("class"))

        result = klass.run
        raise TypeError, "#{row['class']} did not return Deploy::CheckResult" unless result.is_a?(Deploy::CheckResult)
      end
    rescue StandardError, LoadError, NameError => e
      result = Deploy::CheckResult.from_error(e, check: name)
    end
  end

  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  [result, duration_ms, output]
end

def record(name, result, duration_ms)
  verification = Master::Execution::Contract::VerificationResult.from_check_result(
    result,
    id: "#{RUN_ID}:#{Digest::SHA256.hexdigest(name.to_s)[0, 12]}",
    subject: name,
    verifier: "pub4-check-runner",
    scope: CHECKS_FILE,
  )
  LEDGER.record(
    check: name,
    outcome: result.outcome,
    run_id: RUN_ID,
    failures: result.failures.size,
    warnings: result.warnings.size,
    errors: result.errors.size,
    duration_ms:,
    verification: verification.to_h,
  )
end

def explain
  registry.each do |name, row|
    row ||= {}
    pass = row["pass"]
    puts format("  %-24s %s", name, pass ? "pass: #{pass}" : "script: #{row['script'] || 'registered'}")
  end
  puts "  CHECK_AUDITOR_STRICT advisory"
  puts "  CHECK_STRICT_INCONCLUSIVE blocks inconclusive checks"
  puts "  CHECK_STRICT_ERRORS blocks errored checks"

  puts "  CHECK_STRICT_SOFT promotes soft failures"
  puts "  CHECKS_FILE selects the check registry"
  puts "  CHECK_AUTOFIX controls check autofix where supported"
  puts "  CHECK_SURFACES narrows the rendered surfaces to the named prefixes"
  puts "  CHECK_SNAPSHOT_UPDATE rewrites layout snapshots instead of comparing them"
  puts "  VISUAL_STRICT fails on accessibility and console findings instead of warning"
  puts "  VISUAL_DRIFT_MAX_RATIO fails pixel drift above this ratio"
end

def ledger_report
  LEDGER.render
end

def parse_options
  options = { all: false, explain: false, ledger: false, args: [] }
  parser = OptionParser.new do |opts|
    opts.on("--all") { options[:all] = true }
    opts.on("--explain") { options[:explain] = true }
    opts.on("--ledger") { options[:ledger] = true }
    opts.on("--no-autofix") { ENV["CHECK_AUTOFIX"] = "0" }

    opts.on("--scan-only") { ENV["CHECK_AUTOFIX"] = "0" }
    opts.on("-h", "--help") { puts opts; exit }
  end
  parser.parse!(ARGV)
  options[:args] = ARGV
  options
end

options = parse_options
if options[:explain]
  explain
  exit 0
end
if options[:ledger]
  ledger_report
  exit 0
end

names = selected_names(all: options[:all], requested: options[:args])
names = registry.keys if names.empty?
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results = {}

names.each_with_index do |name, index|
  note_progress(index + 1, names.size, name)
  row = registry.fetch(name) || {}
  result, duration_ms, output = run_check(name, row, options[:args])
  record(name, result, duration_ms)
  results[name] = result

  outcome = result.outcome
  if outcome == :passed
    result.render(row["pass"]) if %w[
      css_constitution design_metrics rendered_suite layout_suite flow_journey page_simulation mobile_flow
    ].include?(name)

    log_retired("#{CHECK_UNIT} at #{CHECK_PARENT}: #{name} passed")
  else
    result.render
    verdict = outcome == :errored ? 'errored, blocked nothing' : outcome
    down = outcome == :inconclusive ? Deploy::FlowCoverage.down_apps(result) : []
    say(["#{name} #{verdict}", ("skipped:app-down #{down.join(',')}" unless down.empty?),
         (result.gaps.values.first&.clause if outcome == :inconclusive)].compact.join(", "))
  end
end

# Last, because it reports on the checks above: what they asked the token map
# for and did not get. Skipped when none of them read it, as on a single-check
# run of a check that has no thresholds.
token_reads = Deploy::TokenReads.result
unless token_reads.outcome == :inconclusive
  record("token_reads", token_reads, 0)

  results["token_reads"] = token_reads
  token_reads.render
  say("token_reads #{token_reads.outcome}")
end

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
passed = results.count { |_name, result| result.outcome == :passed }
failed = results.select { |_name, result| result.outcome == :failed }.keys
errored = results.select { |_name, result| result.outcome == :errored }.keys
inconclusive = results.select { |_name, result| result.outcome == :inconclusive }.keys
live_skips = results.values.sum(&:live_skips)
autofix = Deploy::CheckAutofix.enabled? ? "on" : "off"

summary = "#{passed} pass, #{failed.size} fail, #{live_skips} skip, #{inconclusive.size} inconclusive, #{errored.size} error"
summary += " in #{format('%.1fs', elapsed)}, autofix #{autofix}"
summary += "; failed=#{failed.join(',')}" unless failed.empty?
summary += "; inconclusive=#{inconclusive.join(',')}" unless inconclusive.empty?
summary += "; errored=#{errored.join(',')}" unless errored.empty?
say(summary)

exit 1 if failed.any?
exit 1 if errored.any? && Deploy::CheckResult.strict_errors?
exit 1 if inconclusive.any? && Deploy::CheckResult.strict_inconclusive?
exit 0
