# frozen_string_literal: true

require "pathname"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  class FrontendAuditorGate
    ROOT = File.expand_path("../../..", __dir__)
    APPS = %w[amber brgen bsdports].freeze
    SHARED = Pathname.new(File.join(ROOT, "RAILS", "shared"))

    def self.run
      result = GateResult.new
      load SHARED.join("app/services/shared/frontend_auditor.rb")

      count = (APPS + ["shared"]).sum do |app|
        root = app == "shared" ? SHARED : Pathname.new(File.join(ROOT, "RAILS", app))
        Shared::FrontendAuditor.call(root: root).count { |finding| %i[error warning].include?(finding.severity) }
      end

      result.fail("auditor findings: #{count}") if count.positive?
      result
    end
  end
end