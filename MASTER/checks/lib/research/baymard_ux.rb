# frozen_string_literal: true

require_relative "../../support/check_result"

module Deploy
  # Source-level Baymard profile audit plus an explicit ledger of the rendered
  # and participant evidence that the current run does not claim to have.
  class BaymardUxCheck
    ROOT = File.expand_path("../../../..", __dir__)
    APPS = Master::BaymardAudit::DEFAULT_APPS

    def self.run(root: ROOT, apps: APPS, evidence: {})
      require File.join(root, "MASTER", "lib", "master") unless defined?(Master::ROOT)
      require File.join(root, "MASTER", "lib", "baymard_audit")
      report = Master::BaymardAudit.audit_tree(
        rails_root: File.join(root, "RAILS"),
        apps:,
        evidence:,
        master_root: File.join(root, "MASTER"),
      )
      result = CheckResult.new
      measured = report.findings.count do |finding|
        finding.mode == "source" && finding.status != "INCONCLUSIVE"
      end
      result.checked!(measured) if measured.positive?

      report.findings.each do |finding|
        label = [finding.app, finding.path, finding.check_id].compact.join("/")
        case finding.status
        when "FAIL"
          severity = finding.severity == "warning" ? :soft : :hard
          result.fail("baymard UX #{label}: #{finding.message}", severity:)
        when "INCONCLUSIVE"
          result.inconclusive!("baymard UX #{label}: #{finding.message}")
        end
      end

      result.warn(report.line)
      result.warn("baymard UX: rendered-browser and participant-task evidence remains INCONCLUSIVE until supplied")
        if report.findings.any?(&:inconclusive?)
      result
    rescue StandardError => e
      CheckResult.from_error(e, check: "BaymardUxCheck")
    end
  end
end
