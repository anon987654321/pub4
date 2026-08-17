# frozen_string_literal: true

require "pathname"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class FrontendAuditorGate
    ROOT = File.expand_path("../../../..", __dir__)
    APPS = %w[amber brgen bsdports].freeze
    SHARED = Pathname.new(File.join(ROOT, "RAILS", "shared"))

    # GATE_AUDITOR_STRICT=1 fails on warnings (old behavior).
    # Default: only :error findings block layout_suite; warnings are reported.
    def self.strict_warnings?(env = ENV)
      %w[1 true yes on].include?(env["GATE_AUDITOR_STRICT"].to_s.strip.downcase)
    end

    def self.run
      result = GateResult.new
      load SHARED.join("app/services/shared/frontend_auditor.rb")

      by_app = {}
      errors = 0
      warnings = 0

      (APPS + ["shared"]).each do |app|
        root = app == "shared" ? SHARED : Pathname.new(File.join(ROOT, "RAILS", app))
        findings = Shared::FrontendAuditor.call(root: root)
        errs = findings.select { |f| f.severity == :error }
        warns = findings.select { |f| f.severity == :warning }
        infos = findings.select { |f| f.severity == :info }
        by_app[app] = { errors: errs.size, warnings: warns.size, info: infos.size }
        errors += errs.size
        warnings += warns.size

        errs.first(5).each do |f|
          result.fail("auditor error [#{app}] #{f.path}: #{f.rule} — #{f.message}")
        end
        warns.first(8).each do |f|
          result.warn("auditor warning [#{app}] #{f.path}: #{f.rule} — #{f.message}")
        end
        # Pen allow-list hits are info — surface count only
        pen_infos = infos.count { |f| f.rule == :product_pen }
        result.warn("auditor [#{app}]: #{errs.size} error(s), #{warns.size} warning(s), #{pen_infos} product pen(s) preserved") if findings.any?
      end

      summary = by_app.map { |app, c| "#{app}=e#{c[:errors]}/w#{c[:warnings]}" }.join(" ")
      result.warn("auditor summary: #{summary}")

      if errors.positive?
        result.fail("auditor findings: #{errors} error(s) across apps")
      elsif warnings.positive? && strict_warnings?
        result.fail("auditor findings: #{warnings} warning(s) (GATE_AUDITOR_STRICT=1)")
      elsif warnings.positive?
        result.warn("auditor: #{warnings} warning(s) non-blocking (set GATE_AUDITOR_STRICT=1 to fail)")
      end

      result
    end
  end
end
