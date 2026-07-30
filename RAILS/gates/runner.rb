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

require "optparse"
require "rbconfig"
require "yaml"

GATES_DIR = __dir__
RAILS_ROOT = File.expand_path("..", __dir__)
REPO_ROOT = File.expand_path("../..", __dir__)

GATES = YAML.safe_load_file(File.join(GATES_DIR, "gates.yml")).freeze

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
end

def emit_gate_result(key, result, verbose:)
  unless result.respond_to?(:render)
    warn "[gates] #{key}: in-process gate did not return Deploy::GateResult"
    return :failed
  end

  autofix_off = ENV["GATE_AUTOFIX"].to_s.strip.downcase.match?(/\A(0|false|no|off)\z/)
  warn "[gates] GATE_AUTOFIX #{autofix_off ? 'off (report-only)' : 'on (fix + remeasure)'}"

  # GateResult owns both the rendering and the three-way classification. A gate
  # that could not run its check is not a pass: it does not block the suite (off
  # the deploy host most rendered gates genuinely cannot run), but it must not be
  # counted in the "ALL PASSED" line either. run_one prints the outcome label.
  #
  # The gate's own pass line only prints when it was asked for by name, which is
  # how it used to be invoked directly. Under --all the suite summary speaks for
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
  system(*ruby_cmd, path, *extra)
  # A subprocess only tells us its exit status, so an inconclusive gate run this
  # way still reads as a pass here. Its own output names what it skipped.
  $?.success? ? :passed : :failed
end

OUTCOME_LABEL = { passed: "PASSED", failed: "FAILED", inconclusive: "INCONCLUSIVE (checked nothing)" }.freeze

def run_one(key, verbose:)
  row = GATES.fetch(key)
  source = subprocess?(row) ? row["script"] : row["class"]
  puts "\n==> [gates] Running #{key} (#{source})"
  outcome = subprocess?(row) ? run_subprocess(key, row) : run_in_process(key, row, verbose:)
  puts "[gates] #{key} #{OUTCOME_LABEL.fetch(outcome)}"
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
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

if options[:list]
  list_gates
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
outcomes = gates_to_run.to_h { |key| [key, run_one(key, verbose:)] }

failed = outcomes.select { |_, o| o == :failed }.keys
unchecked = outcomes.select { |_, o| o == :inconclusive }.keys
passed = outcomes.count { |_, o| o == :passed }

puts "\n#{'=' * 50}"
if failed.any?
  puts "[gates] SOME GATES FAILED: #{failed.join(', ')}"
elsif unchecked.any?
  # Never claim a coverage number the run did not earn. This line is the whole
  # point of the third state: "ALL PASSED (24)" used to include gates that had
  # no Chrome, no listening app and nothing to measure.
  puts "[gates] #{passed} gate(s) passed, #{unchecked.size} inconclusive: #{unchecked.join(', ')}"
else
  puts "[gates] ALL SELECTED GATES PASSED (#{passed})"
end
exit failed.any? ? 1 : 0
