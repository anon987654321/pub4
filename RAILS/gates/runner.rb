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
  css_minify_integrity:  "css_minify_integrity_gate.rb",
  layout_geometry:       "layout_geometry_gate.rb",
  dialect_purity:        "dialect_purity_gate.rb",
  payment_honesty:       "payment_honesty_gate.rb",
  layout_search:         "layout_search_gate.rb",
  layout_suite:          "layout_suite_gate.rb",
  surface_schema:        "surface_schema_gate.rb",
  design_metrics:        "design_metrics_gate.rb",
  visual_quality:        "visual_quality_gate.rb",
  calibration:           "calibration_gate.rb",
  apps_yml:              "apps_yml_validator.rb",
  shared_wiring:         "shared_wiring_gate.rb",
  constitutional_scan:   "constitutional_scan_gate.rb",
  # Rendered-browser gates (need Chrome + a booted app; degrade to warnings).
  rendered_suite:        "rendered_suite_gate.rb",
  geometry:              "geometry_gate.rb",
  layout_snapshot:       "layout_snapshot_gate.rb",
  journey_invariant:     "journey_invariant_gate.rb",
  reflow:                "reflow_gate.rb",
  keyboard_flow:         "keyboard_flow_gate.rb",
  cross_app:             "cross_app_equivalence_gate.rb",
  # Pure gates (no browser, no running app).
  deploy_drift:          "deploy_drift_gate.rb",
  flow_journey:          "flow_journey_gate.rb",
  gate_mutation:         "gate_mutation_gate.rb",
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
  css_minify_integrity: :layout_suite,
  layout_geometry:     :layout_suite,
  dialect_purity:      :layout_suite,
  payment_honesty:     :layout_suite,
  layout_search:       :layout_suite,
  user_flow:           :layout_suite,
  surface_schema:      :layout_suite,
  design_metrics:      :layout_suite,
  visual_quality:      :layout_suite,
  calibration:         :layout_suite,
  frontend_auditor:    :layout_suite,
  # rendered_suite owns every browser-backed gate; each launches Chrome, so
  # running a leaf twice in one invocation is pure wall-clock waste.
  geometry:            :rendered_suite,
  layout_snapshot:     :rendered_suite,
  journey_invariant:   :rendered_suite,
  reflow:              :rendered_suite,
  keyboard_flow:       :rendered_suite,
  cross_app:           :rendered_suite,
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
  css_minify_integrity:  ["lib/css_minify_integrity_gate", "Deploy::CssMinifyIntegrityGate", {}],
  layout_geometry:       ["lib/layout_geometry_gate", "Deploy::LayoutGeometryGate", {}],
  dialect_purity:        ["lib/dialect_purity_gate", "Deploy::DialectPurityGate", {}],
  payment_honesty:       ["lib/payment_honesty_gate", "Deploy::PaymentHonestyGate", {}],
  layout_search:         ["lib/layout_search_gate", "Deploy::LayoutSearchGate", {}],
  layout_suite:          ["lib/layout_suite_gate", "Deploy::LayoutSuiteGate", {}],
  surface_schema:        ["lib/surface_schema_gate", "Deploy::SurfaceSchemaGate", {}],
  design_metrics:        ["lib/design_metrics_gate", "Deploy::DesignMetricsGate", {}],
  visual_quality:        ["lib/visual_quality_gate", "Deploy::VisualQualityGate", {}],
  calibration:           ["lib/calibration_gate", "Deploy::CalibrationGate", {}],
  rendered_suite:        ["lib/rendered_suite_gate", "Deploy::RenderedSuiteGate", {}],
  geometry:              ["lib/geometry_gate", "Deploy::GeometryGate", {}],
  layout_snapshot:       ["lib/layout_snapshot_gate", "Deploy::LayoutSnapshotGate", {}],
  journey_invariant:     ["lib/journey_invariant_gate", "Deploy::JourneyInvariantGate", {}],
  reflow:                ["lib/reflow_gate", "Deploy::ReflowGate", {}],
  keyboard_flow:         ["lib/keyboard_flow_gate", "Deploy::KeyboardFlowGate", {}],
  cross_app:             ["lib/cross_app_equivalence_gate", "Deploy::CrossAppEquivalenceGate", {}],
  deploy_drift:          ["lib/deploy_drift_gate", "Deploy::DeployDriftGate", {}],
  flow_journey:          ["lib/flow_journey_gate", "Deploy::FlowJourneyGate", {}],
  gate_mutation:         ["lib/gate_mutation_gate", "Deploy::GateMutationGate", {}],
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
  result.render
end

def run_subprocess(key)
  path = gate_path(key)
  unless File.file?(path)
    warn "[gates] Missing gate file for #{key}: #{path}"
    return :failed
  end
  extra = gate_extra_args(key)
  puts "[gates] visual_contract capture enabled (VISUAL_CAPTURE=1)" if key == :visual_contract && extra.include?("--capture")
  system(*ruby_cmd, path, *extra)
  # A subprocess only tells us its exit status, so an inconclusive gate run this
  # way still reads as a pass here. Its own output names what it skipped.
  $?.success? ? :passed : :failed
end

OUTCOME_LABEL = { passed: "PASSED", failed: "FAILED", inconclusive: "INCONCLUSIVE (checked nothing)" }.freeze

def run_one(key)
  path = gate_path(key)
  puts "\n==> [gates] Running #{key} (#{File.basename(path)})"
  outcome =
    if IN_PROCESS.key?(key) && !SUBPROCESS_ONLY.include?(key)
      run_in_process(key)
    else
      run_subprocess(key)
    end
  puts "[gates] #{key} #{OUTCOME_LABEL.fetch(outcome)}"
  outcome
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

outcomes = gates_to_run.to_h { |key| [key, run_one(key)] }

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
