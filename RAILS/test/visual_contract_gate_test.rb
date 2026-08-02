# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gates/visual_contract"

class VisualContractGateTest < Minitest::Test
  def test_each_app_covers_failure_states_and_all_viewports
    VisualContractGate::ROUTES.each_key do |app|
      rows = VisualContractGate.matrix(app)
      %i[empty error offline].each { |state| assert rows.any? { |row| row[:state] == state } }
      assert_equal VisualContractGate::VIEWPORTS.keys.sort, rows.map { |row| row[:viewport] }.uniq.sort
    end
  end

  def test_manifest_schema_records_render_and_accessibility_evidence
    source = File.read(File.expand_path("../gates/visual_contract.rb", __dir__))
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

  # The gate used to print its drift/a11y counts and exit 0 regardless, so a
  # deploy could not fail on anything it saw. These pin what each severity means.
  def row(state:, status:, a11y: [], console: [], diff: nil, ratio: nil)
    { app: :brgen, state:, viewport: :mobile, route: "/x", status:,
      accessibility_violations: a11y, console_errors: console,
      pixel_diff_count: diff, pixel_diff_ratio: ratio }
  end

  def test_server_error_on_a_contract_route_blocks
    verdict = VisualContractGate.grade([row(state: :sign_in, status: 500)])

    assert_equal 1, verdict[:hard].length
    assert_includes verdict[:hard].first, "returned 500"
  end

  def test_the_error_cell_is_allowed_to_be_404
    verdict = VisualContractGate.grade([row(state: :error, status: 404), row(state: :public, status: 200)])

    assert_empty verdict[:hard]
    assert_empty verdict[:soft]
  end

  def test_unmeasured_status_is_not_a_failure
    assert_empty VisualContractGate.grade([row(state: :public, status: nil)])[:hard]
  end

  def test_accessibility_and_console_are_soft_until_strict
    rows = [row(state: :public, status: 200, a11y: %w[image_without_alt], console: ["boom"])]

    lenient = VisualContractGate.grade(rows)
    assert_empty lenient[:hard]
    assert_equal 2, lenient[:soft].length

    strict = VisualContractGate.grade(rows, strict: true)
    assert_equal 2, strict[:hard].length
    assert_empty strict[:soft]
  end

  def test_drift_is_reported_and_only_blocks_against_an_explicit_budget
    rows = [row(state: :public, status: 200, diff: 40, ratio: 0.04)]

    reported = VisualContractGate.grade(rows)
    assert_empty reported[:hard]
    assert_equal 1, reported[:drift][:states]
    assert_equal 40, reported[:drift][:pixels]

    budgeted = VisualContractGate.grade(rows, drift_max: 0.01)
    assert_equal 1, budgeted[:hard].length
    assert_includes budgeted[:hard].first, "VISUAL_DRIFT_MAX_RATIO"
  end

  def test_runner_forwards_visual_capture_env_to_gate
    source = File.read(File.expand_path("../gates/runner.rb", __dir__))
    %w[VISUAL_CAPTURE VISUAL_CAPTURE_APP VISUAL_CAPTURE_BASE visual_contract_capture_args].each do |needle|
      assert_includes source, needle
    end
  end
end
