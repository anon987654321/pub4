#!/usr/bin/env ruby
# frozen_string_literal: true

# One gate runner for MASTER, RAILS and OPENBSD.
# gates/gates.yml is the declaration surface; this file only executes it.

require "open3"
require "optparse"
require "rbconfig"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
GATES_DIR = __dir__
REGISTRY_DEFAULT = File.join(GATES_DIR, "gates.yml")
GATE_UNIT = "gates0"
GATE_PARENT = ENV.fetch("PUB4_DEPLOY_APP", "rails")
SUBPROCESS_INCONCLUSIVE = 3

$LOAD_PATH.unshift(ROOT, GATES_DIR)
require File.join(ROOT, "MASTER", "gates", "support", "gate_result")
require File.join(ROOT, "MASTER", "gates", "support", "gate_ledger")
require File.join(ROOT, "MASTER", "lib", "trace", "dmesg")

GATES_FILE = ENV.fetch("GATES_FILE", REGISTRY_DEFAULT)
GATES = YAML.safe_load_file(GATES_FILE).freeze
LEDGER = Deploy::GateLedger.new
RUN_ID = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{Process.pid}"

def say(detail)
  puts Master::Trace::Dmesg.line(GATE_UNIT, GATE_PARENT, detail)
rescue StandardError
  puts "#{GATE_UNIT} at #{GATE_PARENT}: #{detail}"
end

def log_retired(line)
  path = File.join(File.dirname(LEDGER.path), ".gate_output.log")
  File.open(path, "a") { |io| io.puts(line) }
rescue StandardError
  nil
end

def registry
  GATES
end

def selected_names(all:, requested:)
  names = requested.empty? ? registry.keys : requested
  names = registry.keys if all
  unknown = names.reject { |name| registry.key?(name) }
  abort "gates: unknown gate(s): #{unknown.join(", ")}" unless unknown.empty?
  return names unless all

  names.reject { |name| registry.fetch(name).is_a?(Hash) && registry.fetch(name)["covered_by"] }
end

def constant_for(name)
  name.split("::").inject(Object) { |owner, part| owner.const_get(part, false) }
end

def require_gate(row)
  path = row["require"].to_s
  return if path.empty?

  absolute = if path.start_with?("MASTER/", "OPENBSD/")
               File.join(ROOT, path)
             else
               File.join(GATES_DIR, path)
             end
  require absolute
end

def browser_available?
  %w[google-chrome chromium chromium-browser].any? do |command|
    system("command", "-v", command, out: File::NULL, err: File::NULL)
  end
end

def precondition_result(name, row)
  needs = Array(row["needs"]).map(&:to_s)
  return unless needs.include?("browser")
  return if browser_available?

  Deploy::GateResult.new.inconclusive!("#{name}: browser/Chromium unavailable")
end

def run_script(path, args)
  command = [RbConfig.ruby, path, *args]
  stdout, status = Open3.capture2e(ENV.to_h, *command, chdir: ROOT)
  stdout.to_s.lines.each { |line| log_retired(line.chomp) }
  result = Deploy::GateResult.new
  if status.exitstatus == SUBPROCESS_INCONCLUSIVE
    result.inconclusive!("#{File.basename(path)}: subprocess measured nothing")
  elsif status.success?
    result.checked!
  else
    result.fail("#{File.basename(path)} exited #{status.exitstatus}")
  end
  [result, stdout]
rescue StandardError => e
  [Deploy::GateResult.from_error(e, gate: File.basename(path)), ""]
end

def run_gate(name, row, args)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = precondition_result(name, row)
  output = +""

  if result.nil?
    begin
      require_gate(row)
      if row["script"]
        path = File.join(GATES_DIR, row["script"].to_s)
        result, output = run_script(path, args)
      else
        klass = constant_for(row.fetch("class"))
        result = klass.run
        raise TypeError, "#{row['class']} did not return Deploy::GateResult" unless result.is_a?(Deploy::GateResult)
      end
    rescue StandardError, LoadError, NameError => e
      result = Deploy::GateResult.from_error(e, gate: name)
    end
  end

  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  [result, duration_ms, output]
end

def record(name, result, duration_ms)
  LEDGER.record(
    gate: name,
    outcome: result.outcome,
    run_id: RUN_ID,
    failures: result.failures.size,
    warnings: result.warnings.size,
    errors: result.errors.size,
    duration_ms:
  )
end

def explain
  registry.each do |name, row|
    row ||= {}
    pass = row["pass"]
    puts format("  %-24s %s", name, pass ? "pass: #{pass}" : "script: #{row['script'] || 'registered'}")
  end
  puts "  GATE_AUDITOR_STRICT advisory"
  puts "  GATE_STRICT_INCONCLUSIVE blocks inconclusive gates"
  puts "  GATE_STRICT_ERRORS blocks errored gates"
  puts "  GATE_STRICT_SOFT promotes soft failures"
  puts "  GATES_FILE selects the gate registry"
  puts "  GATE_AUTOFIX controls gate autofix where supported"
  puts "  VISUAL_CAPTURE controls visual capture where supported"
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
    opts.on("--no-autofix") { ENV["GATE_AUTOFIX"] = "0" }
    opts.on("--scan-only") { ENV["GATE_AUTOFIX"] = "0" }
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

names.each do |name|
  row = registry.fetch(name) || {}
  result, duration_ms, output = run_gate(name, row, options[:args])
  record(name, result, duration_ms)
  results[name] = result
  outcome = result.outcome
  if outcome == :passed
    result.render if %w[css_constitution design_metrics].include?(name)
    log_retired("#{GATE_UNIT} at #{GATE_PARENT}: #{name} passed")
  else
    result.render
    say("#{name} #{outcome == :errored ? 'errored, blocked nothing' : outcome}")
  end
end

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
passed = results.count { |_name, result| result.outcome == :passed }
failed = results.select { |_name, result| result.outcome == :failed }.keys
errored = results.select { |_name, result| result.outcome == :errored }.keys
inconclusive = results.select { |_name, result| result.outcome == :inconclusive }.keys
autofix = ENV.fetch("GATE_AUTOFIX", "0") == "1" ? "on" : "off"
problems = (failed + errored + inconclusive).uniq

summary = "#{passed} of #{results.size} passed in #{format('%.1fs', elapsed)}, autofix #{autofix}"
summary += "; #{problems.join(', ')} #{problems.size == 1 ? 'failed' : 'failed'}" unless problems.empty?
say(summary)

exit 1 if failed.any?
exit 1 if errored.any? && Deploy::GateResult.strict_errors?
exit 1 if inconclusive.any? && Deploy::GateResult.strict_inconclusive?
exit 0
