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
# This is the start of the consolidated gates module. Individual gates remain in RAILS/ for now
# (backward compat with existing Gate definitions and bin/check scripts). Future: move gate files into gates/ subdir.

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
}.freeze

def gate_path(name)
  File.expand_path("../../#{GATE_MAP[name]}", __FILE__)
end

def run_one(key)
  path = gate_path(key)
  unless File.file?(path)
    warn "[gates] Missing gate file for #{key}: #{path}"
    return false
  end
  puts "\n==> [gates] Running #{key} (#{File.basename(path)})"
  ruby_runner = File.expand_path("../../../MASTER/lib/pub4/ruby_runner.rb", __FILE__)
  ruby = if File.file?(ruby_runner)
           require ruby_runner
           Pub4::RubyRunner.gate_ruby
         else
           ENV.fetch("RUBY_CMD", "ruby").split
         end
  system(*ruby, path)
  success = $?.success?
  puts success ? "[gates] #{key} PASSED" : "[gates] #{key} FAILED"
  success
end

def list_gates
  puts "Available gates (use short name with runner.rb):"
  GATE_MAP.each { |k, v| puts "  #{k.to_s.ljust(22)} -> #{v}" }
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

gates_to_run = if options[:all] || ARGV.empty?
  GATE_MAP.keys
elsif ARGV.any?
  ARGV.select { |k| GATE_MAP.key?(k) }
else
  []
end

if gates_to_run.empty? && !options[:all]
  warn "No valid gates specified. Use --list or --all or specific names."
  exit 1
end

results = gates_to_run.map do |key|
  run_one(key)
end

overall = results.all?

puts "\n#{'='*50}"
puts overall ? "[gates] ALL SELECTED GATES PASSED (#{results.size})" : "[gates] SOME GATES FAILED"
exit overall ? 0 : 1
