# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../../lib/review/baymard_law"

module Deploy
  # Baymard-informed UX audit for the RAILS fleet. Deterministic source findings
  # are measured here; visitor-task findings require explicit evidence and are
  # never inferred from route names, source text or a model's opinion.
  class BaymardUXCheck
    ROOT = File.expand_path("../../../..", __dir__)

    def self.run(root: ROOT, apps: nil, evidence_path: ENV["BAYMARD_EVIDENCE"])
      new(root:, apps:, evidence_path:).run
    end

    def initialize(root:, apps: nil, evidence_path: nil)
      @root = root
      @apps = apps
      @evidence_path = evidence_path
    end

    def run
      report = Master::Review::BaymardLaw.new(
        root: @root,
        apps: @apps,
        evidence_path: @evidence_path,
      ).call

      result = CheckResult.new
      result.checked!(report.measured_count) if report.measured_count.positive?

      report.findings.each do |finding|
        location = finding.path ? "#{finding.path}:#{finding.line}" : finding.evidence.join(", ")
        detail = [
          "baymard_ux",
          finding.app,
          finding.check_id,
          location,
          finding.message,
          "laws=#{finding.law_ids.join(",")}",
          "verify=#{finding.recommendation}",
        ].reject { |part| part.to_s.empty? }.join(" | ")

        result.fail(detail, severity: finding.severity == "error" ? :hard : :soft)
      end

      report.read_errors.each { |error| result.incomplete!("baymard_ux: source could not be measured — #{error}") }
      if report.apps.empty?
        result.incomplete!("baymard_ux: no RAILS app or shared-engine source root was available")
      end
      if report.inconclusive_count.positive?
        result.incomplete!("baymard_ux: #{report.inconclusive_count} assessment(s) need rendered or task evidence")
      end

      result.warn("baymard_ux: #{report.summary}")
      result.warn("baymard_ux: not an official Baymard score or certification")
      if CheckResult.flag?("BAYMARD_STRICT") && report.inconclusive_count.positive?
        result.fail("baymard_ux: BAYMARD_STRICT=1 requires evidence for every applicable task assessment")
      end
      result
    rescue StandardError => e
      CheckResult.from_error(e, check: "BaymardUXCheck")
    end
  end
end
