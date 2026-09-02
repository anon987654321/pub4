# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../shared/lib/pub4/scale_lint"

module Deploy
  # Pub4::ScaleLint, wired.
  #
  # The lint was written, tested by RAILS/test/scale_lint_test.rb, and reachable
  # from no gate: `runner.rb --list` did not know the name, so nothing ran it and
  # its baselines in design_tokens.yml sat unchecked. That is the inert-wiring
  # shape this tree keeps finding — a declaration with no reader — and it is why
  # off_scale_line_height drifted to 6 against a baseline of 6 without anyone
  # being told.
  #
  # Per surface rather than in total, because the two surfaces have different
  # owners and different budgets: `apps` is the three Rails apps plus the shared
  # engine, `face` is MASTER/web/public. A regression in one must not be masked
  # by a fall in the other, which a single number would allow.
  #
  # A count over its baseline fails. A count under it is reported, not failed —
  # recording the new low is a deliberate edit to design_tokens.yml, the same
  # contract data_reach and spine.yml hold.
  class ScaleRatchetGate
    LINT = Pub4::ScaleLint

    def self.run
      result = GateResult.new
      over = []
      under = []

      LINT::SURFACES.each do |surface|
        baselines = LINT.baselines_for(surface)
        counts = LINT.counts_for(surface)

        baselines.each do |kind, baseline|
          count = counts[kind].to_i
          if count > baseline
            over << "#{surface}.#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})"
          elsif count < baseline
            under << "#{surface}.#{kind}: #{count} (baseline #{baseline}, -#{baseline - count})"
          end
        end
      end

      over.each do |line|
        result.fail("scale_ratchet: #{line}")
      end

      # The nearest declared step, so the report says what to write instead.
      LINT.findings.first(8).each do |finding|
        step = LINT.nearest(finding)
        result.warn("scale_ratchet: #{finding.file}:#{finding.line} #{finding.kind} " \
                    "#{finding.value}#{step ? " — nearest step #{step}" : ""}")
      end

      under.each do |line|
        result.warn("scale_ratchet: new low #{line} — record it in design_tokens.yml scale.baselines")
      end

      totals = LINT::SURFACES.map { |s| "#{s} #{LINT.counts_for(s).values.sum}" }.join(", ")
      result.warn("scale_ratchet: #{totals}")
      result
    end
  end
end
