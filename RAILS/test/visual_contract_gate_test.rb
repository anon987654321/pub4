# frozen_string_literal: true

require "minitest/autorun"
require_relative "../visual_contract_gate"

class VisualContractGateTest < Minitest::Test
  def test_each_app_covers_failure_states_and_all_viewports
    VisualContractGate::ROUTES.each_key do |app|
      rows = VisualContractGate.matrix(app)
      %i[empty error offline].each { |state| assert rows.any? { |row| row[:state] == state } }
      assert_equal VisualContractGate::VIEWPORTS.keys.sort, rows.map { |row| row[:viewport] }.uniq.sort
    end
  end

  def test_manifest_schema_records_render_and_accessibility_evidence
    source = File.read(File.expand_path("../visual_contract_gate.rb", __dir__))
    %w[status title screenshot_sha256 console_errors accessibility_violations].each do |field|
      assert_includes source, "#{field}:"
    end
    assert_equal 5, VisualContractGate::LENSES.length
  end

  def test_runner_forwards_visual_capture_env_to_gate
    source = File.read(File.expand_path("../gates/runner.rb", __dir__))
    %w[VISUAL_CAPTURE VISUAL_CAPTURE_APP VISUAL_CAPTURE_BASE visual_contract_capture_args].each do |needle|
      assert_includes source, needle
    end
  end
end
