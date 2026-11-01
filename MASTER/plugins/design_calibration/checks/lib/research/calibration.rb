# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/check_calibration"

module Deploy
  # P5: human calibration agreement check.
  # Fails hard if agreement < floor. Emits false pos/neg + weight suggestions.
  # CHECK_CALIBRATION_APPLY=1 writes data/calibration_weights.yml for VisualQuality.
  class CalibrationCheck
    def self.run
      new.run
    end

    def run
      @result = CheckResult.new
      unless File.file?(CheckCalibration::DATA)
        @result.fail("calibration: missing #{CheckCalibration::DATA}")
        return @result
      end

      cal = CheckCalibration.new
      report = cal.run

      @result.warn(
        "calibration: agreement=#{(report[:agreement] * 100).round(1)}% " \
        "(#{report[:agreed]}/#{report[:total]}) floor=#{(report[:floor] * 100).round(0)}%",
      )

      # A calibration set with no cases agrees with nothing. CheckCalibration
      # scores it 0%, which is a missing label set rather than a check that
      # disagrees with a human, so it is inconclusive and not also a floor failure.
      if report[:total].to_i.zero?
        @result.inconclusive!("calibration: the labelled set is empty — agreement was computed over no cases")
        return @result
      end

      @result.checked!(report[:total].to_i)

      report[:cases].each do |c|
        mark = c.agree ? "ok" : "DISAGREE"
        @result.warn(
          "calibration [#{mark}] #{c.id}: human=#{c.human} check=#{c.check} " \
          "detail=#{c.detail.inspect}",
        )
      end

      report[:false_positives].each do |c|
        @result.warn("calibration FP (check too harsh): #{c.id} notes=#{c.notes.join(',')}")
      end
      report[:false_negatives].each do |c|
        @result.warn("calibration FN (check too soft): #{c.id} — human fail, check pass")
      end

      report[:suggestions].each do |s|
        @result.warn("calibration suggest: #{s[:message]}")
      end

      unless report[:pass]
        @result.fail(
          "calibration: agreement #{(report[:agreement] * 100).round(1)}% < " \
          "floor #{(report[:floor] * 100).round(0)}% — retune weights or fix labels " \
          "(principle=kaizen)",
        )
      end

      if apply?
        path = cal.apply_weights!(report)
        @result.warn("calibration: wrote weight overrides → #{path.sub(%r{\A.*/MASTER/}, 'MASTER/')}")
      end

      @result
    end

    private

    def apply?
      %w[1 true yes on].include?(ENV["CHECK_CALIBRATION_APPLY"].to_s.strip.downcase)
    end
  end
end
