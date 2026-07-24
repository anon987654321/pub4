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
    %w[status title screenshot_sha256 console_errors accessibility_violations pixel_diff_count pixel_diff_ratio pixel_diff_image].each do |field|
      assert_includes source, "#{field}:"
    end
    assert_equal 5, VisualContractGate::LENSES.length
  end

  def test_pixel_diff_counts_changed_pixels_and_ignores_dimension_mismatch
    require "chunky_png"
    require "tmpdir"

    baseline = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::BLACK)
    changed = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::BLACK)
    changed[0, 0] = ChunkyPNG::Color::WHITE

    Dir.mktmpdir do |dir|
      screenshot_path = File.join(dir, "current.png")
      diff_path = File.join(dir, "diff.png")
      changed.save(screenshot_path)

      result = VisualContractGate.pixel_diff(baseline_bytes: baseline.to_blob, screenshot_path:, diff_path:)
      assert_equal 1, result[:pixel_diff_count]
      assert_equal 0.25, result[:pixel_diff_ratio]
      assert File.file?(diff_path)

      resized = ChunkyPNG::Image.new(3, 3, ChunkyPNG::Color::BLACK)
      resized.save(screenshot_path)
      mismatch = VisualContractGate.pixel_diff(baseline_bytes: baseline.to_blob, screenshot_path:, diff_path:)
      assert_nil mismatch[:pixel_diff_count]
      assert_nil mismatch[:pixel_diff_image]
    end
  rescue LoadError
    skip "chunky_png not available outside an app bundle"
  end

  def test_runner_forwards_visual_capture_env_to_gate
    source = File.read(File.expand_path("../gates/runner.rb", __dir__))
    %w[VISUAL_CAPTURE VISUAL_CAPTURE_APP VISUAL_CAPTURE_BASE visual_contract_capture_args].each do |needle|
      assert_includes source, needle
    end
  end
end
