#!/usr/bin/env ruby
# frozen_string_literal: true

# Consolidated Rails Gates Runner
# Provides a single entrypoint for the many production/readiness/visual/etc. gates.
#
# Usage:
#   ruby RAILS/gates/runner.rb --all
#   ruby RAILS/gates/runner.rb production domain_alignment
#   ruby RAILS/gates/runner.rb --list
#
# Composite gates (production, release) already run their leaf checks in-process.
# --all deduplicates those leaves so each logical gate runs once.

require "optparse"

GATE_MAP = {
  production:            "check_production_gate.rb",
  domain_alignment:      "domain_alignment_gate.rb",
  frontend_auditor:      "frontend_auditor_gate.rb",
  frontend_production:   "frontend_production_gate.rb",
  generated_asset:       "generated_asset_freshness_gate.rb",
  human_walkthrough:     "human_walkthrough_gate.rb",
  master_tts:            "master_tts_gate.rb",
  master_web_assets:     "master_web_assets_gate.rb",
  phantom_foreign_keys:  "check_phantom_foreign_keys.rb",
  port_inventory:        "port_inventory_gate.rb",
  rails_runtime:         "rails_runtime_gate.rb",
  release:               "release_gate.rb",
  schema_migration:      "schema_migration_gate.rb",
  stimulus_components:   "stimulus_components_adoption_gate.rb",
  visual_contract:       "visual_contract_gate.rb",
  apps_yml:              "gates/apps_yml_validator.rb",
  shared_wiring:         "gates/shared_wiring_gate.rb",
}.freeze

# Leaf gates already executed inside a composite gate on the same runner invocation.
GATE_COVERED_BY = {
  apps_yml:          :production,
  master_web_assets: :production,
  master_tts:        :production,
  domain_alignment:  :release,
  frontend_production: :release,
  frontend_auditor:  :release,
  stimulus_components: :release,
}.freeze

def gate_path(name)
  File.expand_path("../../#{GATE_MAP[name]}", __FILE__)
end

def ruby_cmd
  ruby_runner = File.expand_path("../../../MASTER/lib/pub4/ruby_runner.rb", __FILE__)
  if File.file?(ruby_runner)
    require ruby_runner
    Pub4::RubyRunner.gate_ruby
  else
    ENV.fetch("RUBY_CMD", "ruby").split
  end
end

def resolve_gates(keys)
  keys.reject do |key|
    parent = GATE_COVERED_BY[key]
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
  key == :visual_contract ? visual_contract_capture_args : []
end

def run_one(key)
  path = gate_path(key)
  unless File.file?(path)
    warn "[gates] Missing gate file for #{key}: #{path}"
    return false
  end
  extra = gate_extra_args(key)
  puts "\n==> [gates] Running #{key} (#{File.basename(path)})"
  puts "[gates] visual_contract capture enabled (VISUAL_CAPTURE=1)" if key == :visual_contract && extra.include?("--capture")
  system(*ruby_cmd, path, *extra)
  success = $?.success?
  puts success ? "[gates] #{key} PASSED" : "[gates] #{key} FAILED"
  success
end

def list_gates
  puts "Available gates (use short name with runner.rb):"
  GATE_MAP.each { |k, v| puts "  #{k.to_s.ljust(22)} -> #{v}" }
  puts
  puts "Composite gates (skip these leaves when the parent is also selected):"
  GATE_COVERED_BY.group_by(&:last).each do |parent, pairs|
    leaves = pairs.map(&:first).join(", ")
    puts "  #{parent} includes: #{leaves}"
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

ARGV.map!(&:to_sym)

requested = if options[:all] || ARGV.empty?
  GATE_MAP.keys
elsif ARGV.any?
  ARGV.select { |k| GATE_MAP.key?(k) }
else
  []
end

if requested.empty? && !options[:all]
  warn "No valid gates specified. Use --list or --all or specific names."
  exit 1
end

gates_to_run = resolve_gates(requested)
skipped = requested - gates_to_run
if skipped.any?
  puts "[gates] Skipping #{skipped.join(', ')} (covered by composite gates in this run)"
end

results = gates_to_run.map { |key| run_one(key) }

overall = results.all?

puts "\n#{'='*50}"
puts overall ? "[gates] ALL SELECTED GATES PASSED (#{results.size})" : "[gates] SOME GATES FAILED"
exit overall ? 0 : 1