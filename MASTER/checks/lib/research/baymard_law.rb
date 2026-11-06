# frozen_string_literal: true

require_relative "../../support/check_result"
# The review law reads profiles and evidence through Master.load_yaml, which only
# exists after lib/master.rb extends DataLoading. Minitest gets it from test_helper;
# the check runner loads this file alone, so it boots the owner here.
require_relative "../../../lib/master"
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

    private def record_assessments(result, report)
      report.assessments.each do |assessment|
        evidence = assessment.evidence.empty? ? "" : " evidence=#{assessment.evidence.join(";")}"
        result.warn(
          "baymard_ux: #{assessment.app}/#{assessment.check_id}=#{assessment.status.upcase} " \
          "measured=#{assessment.measured}#{evidence}",
        )
      end
    end

    def run
      report = Master::Review::BaymardLaw.new(
        root: @root,
        apps: @apps,
        evidence_path: @evidence_path,
      ).call

      result = CheckResult.new
      result.checked!(report.measured_count) if report.measured_count.positive?

      record_assessments(result, report)

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

      report.read_errors.each { |error| result.incomplete!("baymard_ux: source could not be measured - #{error}") }
      if report.apps.empty?
        result.incomplete!("baymard_ux: no RAILS app or shared-engine source root was available")
      end
      if report.inconclusive_count.positive?
        result.incomplete!("baymard_ux: #{report.inconclusive_count} assessment(s) need rendered or task evidence")
      end

      result.warn("baymard_ux: #{report.summary}")
      result.warn(
        "baymard_ux: /fix does not recruit participants, run real screen-reader sessions or conduct " \
        "conversion experiments; those remain human evidence inputs",
      )
      result.warn("baymard_ux: not an official Baymard score or certification")
      if CheckResult.flag?("BAYMARD_STRICT") && report.task_inconclusive_count.positive?
        result.fail("baymard_ux: BAYMARD_STRICT=1 requires evidence for every applicable participant-task assessment")
      end
      result
    rescue StandardError => e
      CheckResult.from_error(e, check: "BaymardUXCheck")
    end
  end
end
