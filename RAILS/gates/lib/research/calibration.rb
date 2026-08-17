# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/gate_calibration"

module Deploy
  # P5: human calibration agreement gate.
  # Fails hard if agreement < floor. Emits false pos/neg + weight suggestions.
  # GATE_CALIBRATION_APPLY=1 writes data/calibration_weights.yml for VisualQuality.
  class CalibrationGate
    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      unless File.file?(GateCalibration::DATA)
        @result.fail("calibration: missing #{GateCalibration::DATA}")
        return @result
      end

      cal = GateCalibration.new
      report = cal.run

      @result.warn(
        "calibration: agreement=#{(report[:agreement] * 100).round(1)}% " \
        "(#{report[:agreed]}/#{report[:total]}) floor=#{(report[:floor] * 100).round(0)}%"
      )

      report[:cases].each do |c|
        mark = c.agree ? "ok" : "DISAGREE"
        @result.warn(
          "calibration [#{mark}] #{c.id}: human=#{c.human} gate=#{c.gate} " \
          "detail=#{c.detail.inspect}"
        )
      end

      report[:false_positives].each do |c|
        @result.warn("calibration FP (gate too harsh): #{c.id} notes=#{c.notes.join(',')}")
      end
      report[:false_negatives].each do |c|
        @result.warn("calibration FN (gate too soft): #{c.id} — human fail, gate pass")
      end

      report[:suggestions].each do |s|
        @result.warn("calibration suggest: #{s[:message]}")
      end

      unless report[:pass]
        @result.fail(
          "calibration: agreement #{(report[:agreement] * 100).round(1)}% < " \
          "floor #{(report[:floor] * 100).round(0)}% — retune weights or fix labels " \
          "(principle=kaizen)"
        )
      end

      if apply?
        path = cal.apply_weights!(report)
        @result.warn("calibration: wrote weight overrides → #{path.sub(%r{.*/RAILS/}, 'RAILS/')}")
      end

      @result
    end

    private

    def apply?
      %w[1 true yes on].include?(ENV["GATE_CALIBRATION_APPLY"].to_s.strip.downcase)
    end
  end
end
