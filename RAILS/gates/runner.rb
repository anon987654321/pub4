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
# Most gates run in-process via Deploy::* classes returning GateResult.
# Composite gates (production, release) already run their leaf checks.
# --all deduplicates those leaves so each logical gate runs once.
# release / rails_runtime / visual_contract still subprocess (bundle steps / capture args).

require "optparse"
require "rbconfig"

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
  user_flow:             "user_flow_gate.rb",
  css_constitution:      "css_constitution_gate.rb",
  layout_geometry:       "layout_geometry_gate.rb",
  dialect_purity:        "dialect_purity_gate.rb",
  payment_honesty:       "payment_honesty_gate.rb",
  layout_search:         "layout_search_gate.rb",
  layout_suite:          "layout_suite_gate.rb",
  surface_schema:        "surface_schema_gate.rb",
  design_metrics:        "design_metrics_gate.rb",
  visual_quality:        "visual_quality_gate.rb",
  apps_yml:              "apps_yml_validator.rb",
  shared_wiring:         "shared_wiring_gate.rb",
  constitutional_scan:   "constitutional_scan_gate.rb",
}.freeze

# Leaf gates already executed inside a composite gate on the same runner invocation.
GATE_COVERED_BY = {
  apps_yml:            :production,
  master_web_assets:   :production,
  master_tts:          :production,
  domain_alignment:    :release,
  frontend_production: :release,
  stimulus_components: :release,
  # layout_suite owns the professional layout + CSS stack (includes frontend_auditor)
  css_constitution:    :layout_suite,
  layout_geometry:     :layout_suite,
  dialect_purity:      :layout_suite,
  payment_honesty:     :layout_suite,
  layout_search:       :layout_suite,
  user_flow:           :layout_suite,
  surface_schema:      :layout_suite,
  design_metrics:      :layout_suite,
  visual_quality:      :layout_suite,
  frontend_auditor:    :layout_suite,
}.freeze

# In-process Deploy::* callables. Value is [relative require under gates/, class name, optional kwargs].
IN_PROCESS = {
  production:            ["lib/production_gate", "Deploy::ProductionGate", {}],
  domain_alignment:      ["lib/domain_alignment_gate_logic", "Deploy::DomainAlignmentGate", {}],
  frontend_auditor:      ["lib/frontend_auditor_gate_logic", "Deploy::FrontendAuditorGate", {}],
  frontend_production:   ["lib/frontend_production_gate_logic", "Deploy::FrontendProductionGate", {}],
  generated_asset:       ["lib/generated_asset_gate", "Deploy::GeneratedAssetGate", {}],
  human_walkthrough:     ["lib/human_walkthrough_gate", "Deploy::HumanWalkthroughGate", {}],
  master_tts:            ["lib/master_tts_gate", "Deploy::MasterTtsGate", {}],
  master_web_assets:     ["lib/master_web_assets_gate", "Deploy::MasterWebAssetsGate", {}],
  phantom_foreign_keys:  ["lib/phantom_foreign_keys_gate", "Deploy::PhantomForeignKeysGate", {}],
  port_inventory:        ["lib/port_inventory_gate", "Deploy::PortInventoryGate", {}],
  schema_migration:      ["lib/schema_migration_gate", "Deploy::SchemaMigrationGate", {}],
  stimulus_components:   ["lib/stimulus_components_gate", "Deploy::StimulusComponentsGate", {}],
  apps_yml:              ["lib/apps_yml_validator", "Deploy::AppsYmlValidator", {}],
  shared_wiring:         ["lib/shared_wiring_gate", "Deploy::SharedWiringGate", {}],
  constitutional_scan:   ["lib/constitutional_scan_gate", "Deploy::ConstitutionalScanGate", {}],
  user_flow:             ["lib/user_flow_gate", "Deploy::UserFlowGate", {}],
  css_constitution:      ["lib/css_constitution_gate", "Deploy::CssConstitutionGate", {}],
  layout_geometry:       ["lib/layout_geometry_gate", "Deploy::LayoutGeometryGate", {}],
  dialect_purity:        ["lib/dialect_purity_gate", "Deploy::DialectPurityGate", {}],
  payment_honesty:       ["lib/payment_honesty_gate", "Deploy::PaymentHonestyGate", {}],
  layout_search:         ["lib/layout_search_gate", "Deploy::LayoutSearchGate", {}],
  layout_suite:          ["lib/layout_suite_gate", "Deploy::LayoutSuiteGate", {}],
  surface_schema:        ["lib/surface_schema_gate", "Deploy::SurfaceSchemaGate", {}],
  design_metrics:        ["lib/design_metrics_gate", "Deploy::DesignMetricsGate", {}],
  visual_quality:        ["lib/visual_quality_gate", "Deploy::VisualQualityGate", {}],
}.freeze

# Keep subprocess for multi-step / arg-forwarding gates.
SUBPROCESS_ONLY = %i[release rails_runtime visual_contract].freeze

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

def run_in_process(key)
  rel, class_name, kwargs = IN_PROCESS.fetch(key)
  require_relative rel
  klass = Object.const_get(class_name)
  result = kwargs.empty? ? klass.run : klass.run(**kwargs)
  emit_gate_result(key, result)
end

def emit_gate_result(key, result)
  unless result.respond_to?(:ok?)
    warn "[gates] #{key}: in-process gate did not return GateResult"
    return false
  end

  autofix_off = ENV["GATE_AUTOFIX"].to_s.strip.downcase.match?(/\A(0|false|no|off)\z/)
  warn "[gates] GATE_AUTOFIX #{autofix_off ? 'off (report-only)' : 'on (fix + remeasure)'}"

  result.warnings.each { |warning| warn "  - #{warning}" } if result.warnings.any?
  if result.ok?
    true
  else
    warn "Failures:"
    result.failures.each { |failure| warn "  - #{failure}" }
    false
  end
end

def run_subprocess(key)
  path = gate_path(key)
  unless File.file?(path)
    warn "[gates] Missing gate file for #{key}: #{path}"
    return false
  end
  extra = gate_extra_args(key)
  puts "[gates] visual_contract capture enabled (VISUAL_CAPTURE=1)" if key == :visual_contract && extra.include?("--capture")
  system(*ruby_cmd, path, *extra)
  $?.success?
end

def run_one(key)
  path = gate_path(key)
  puts "\n==> [gates] Running #{key} (#{File.basename(path)})"
  success =
    if IN_PROCESS.key?(key) && !SUBPROCESS_ONLY.include?(key)
      run_in_process(key)
    else
      run_subprocess(key)
    end
  puts success ? "[gates] #{key} PASSED" : "[gates] #{key} FAILED"
  success
end

def list_gates
  puts "Available gates (use short name with runner.rb):"
  GATE_MAP.each { |k, v| puts "  #{k.to_s.ljust(22)} -> #{v}" }
  puts
  puts "In-process (Deploy::GateResult): #{IN_PROCESS.keys.join(', ')}"
  puts "Subprocess only: #{SUBPROCESS_ONLY.join(', ')}"
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

puts "\n#{'=' * 50}"
puts overall ? "[gates] ALL SELECTED GATES PASSED (#{results.size})" : "[gates] SOME GATES FAILED"
exit overall ? 0 : 1
