# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../../tools/scale_lint"

module Deploy
  # Operator::ScaleLint, wired.
  #
  # The lint was written, tested by RAILS/test/scale_lint_test.rb, and reachable
  # from no check: `runner.rb --list` did not know the name, so nothing ran it and
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
  class ScaleRatchetCheck
    LINT = Operator::ScaleLint

    # Every baseline against its count, as two lists of message lines. Separated
    # from #run because comparing is one job and reporting is another, and only
    # the first knows what the numbers mean.
    def self.compare(result)
      over = []
      under = []

      LINT::SURFACES.each do |surface|
        baselines = LINT.baselines_for(surface)
        counts = LINT.counts_for(surface)

        baselines.each do |kind, baseline|
          result.checked!
          count = counts[kind].to_i

          if count > baseline
            over << "#{surface}.#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})"
          elsif count < baseline
            under << "#{surface}.#{kind}: #{count} (baseline #{baseline}, -#{baseline - count})"
          end
        end
      end

      compiled(result)

      # A surface with no baselines compares nothing, and a lint that read no
      # files reports zero for every kind, which is indistinguishable from clean.
      result.inconclusive!("scale_ratchet: no baselines declared for any surface - design_tokens.yml scale.baselines is unread") if result.checks_ran.zero?

      [over, under]
    end

    CENSUS = Operator::ScaleLint::Census

    # Distinct values per property in each app's compiled CSS against
    # scale.baselines.compiled. Soft while the counts are young: they were first
    # measured 2026-11-06 from builds that lag origin, and a hard ratchet on a
    # number nobody has watched move would fail a deploy for a stylesheet's
    # history rather than for drift.
    def self.compiled(result, rails_root: LINT::RAILS_ROOT)
      baselines = compiled_baselines
      builds = CENSUS.builds(rails_root)
      (baselines.keys - builds.keys).each do |app|
        result.warn("scale_ratchet: compiled.#{app} not measured - no #{CENSUS::BUILD}")
      end
      builds.slice(*baselines.keys).each { |app, path| compiled_app(result, app, path, baselines.fetch(app)) }
    end

    # tokens.yml scale.baselines "compiled.<app>.<property>" rows, as app => property => baseline.
    def self.compiled_baselines
      rows = LINT.baselines.select { |key, _value| key.start_with?("compiled.") }
      rows.each_with_object(Hash.new { |hash, app| hash[app] = {} }) do |(key, baseline), apps|
        _prefix, app, prop = key.split(".", 3)
        apps[app][prop] = baseline
      end
    end

    def self.compiled_app(result, app, path, baselines)
      counts = CENSUS.counts(File.read(path))
      baselines.each { |prop, baseline| ratchet(result, "compiled.#{app}.#{prop}", [counts[prop].to_i, baseline]) }
    end

    def self.ratchet(result, name, measured)
      count, baseline = measured
      result.checked!
      if count > baseline
        over = "scale_ratchet: #{name}: #{count} (baseline #{baseline}, +#{count - baseline})"
        return result.fail(over, severity: :soft)
      end

      result.warn("scale_ratchet: new low #{name}: #{count} (baseline #{baseline})") if count < baseline
    end

    def self.run
      result = CheckResult.new
      over, under = compare(result)

      over.each do |line|
        result.fail("scale_ratchet: #{line}")
      end

      # The nearest declared step, so the report says what to write instead.
      LINT.findings.first(8).each do |finding|
        step = LINT.nearest(finding)
        result.warn("scale_ratchet: #{finding.file}:#{finding.line} #{finding.kind} " \
                    "#{finding.value}#{step ? " - nearest step #{step}" : ""}")
      end

      under.each do |line|
        result.warn("scale_ratchet: new low #{line} - record it in design_tokens.yml scale.baselines")
      end

      totals = LINT::SURFACES.map { |s| "#{s} #{LINT.counts_for(s).values.sum}" }.join(", ")
      result.warn("scale_ratchet: #{totals}")
      result
    end
  end
end
