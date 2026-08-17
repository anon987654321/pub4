# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../../gates/support/gate_calibration"
require_relative "../../gates/lib/research/calibration"
require_relative "../../../OPENBSD/lib/gate_result"

class CalibrationTest < Minitest::Test
  def setup
    @cal = Deploy::GateCalibration.new
  end

  def test_calibration_yml_loads
    data = Deploy::GateCalibration.load
    assert data["labels"].is_a?(Array)
    assert data["labels"].size >= 10
    assert data["agreement_floor"].to_f >= 0.8
  end

  def test_agreement_meets_floor_on_seed_set
    report = @cal.run
    assert report[:total] >= 10
    assert report[:pass], "agreement=#{report[:agreement]} cases=#{disagree_summary(report)}"
    assert report[:agreement] >= report[:floor]
  end

  def test_known_good_and_bad_agree
    report = @cal.run
    by_id = report[:cases].to_h { |c| [c.id, c] }
    assert by_id["marketplace_tile_good"].agree
    assert by_id["marketplace_tile_bad"].agree
    assert_equal "pass", by_id["marketplace_tile_good"].gate
    assert_equal "fail", by_id["marketplace_tile_bad"].gate
  end

  def test_false_negative_detection
    # If human says fail and we force gate pass logic — covered by seed bads agreeing
    report = @cal.run
    assert report[:false_negatives].empty?, report[:false_negatives].map(&:id).inspect
  end

  def test_apply_weights_writes_file
    path = Deploy::GateCalibration::WEIGHTS_OUT
    FileUtils.rm_f(path)
    out = @cal.apply_weights!
    assert_equal path, out
    assert File.file?(path)
    data = YAML.safe_load_file(path)
    assert data["quality_weights"].is_a?(Hash)
    assert data["quality_weights"]["landmarks"]
  ensure
    FileUtils.rm_f(path)
  end

  def test_calibration_gate_ok
    result = Deploy::CalibrationGate.run
    assert result.ok?, result.failures.join("\n")
  end

  private

  def disagree_summary(report)
    report[:cases].reject(&:agree).map { |c| "#{c.id}:h=#{c.human}/g=#{c.gate}" }.join("; ")
  end
end
