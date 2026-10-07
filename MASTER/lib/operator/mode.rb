# frozen_string_literal: true

module Master
  module Operator
    # One explicit execution contract for agent work. Mode is derived before the
    # first effect and never grants authority beyond constitutional law.
    module Mode
      SPECS = {
        observe: { profile: :observe, risk: :low, model_tier: :cheap, council: false, evidence: :observed },
        plan: { profile: :plan, risk: :medium, model_tier: :fast, council: false, evidence: :observed_or_inferred },
        repair: { profile: :repair, risk: :high, model_tier: :strong, council: true, evidence: :verified },
        deploy: { profile: :deploy, risk: :critical, model_tier: :strong, council: true, evidence: :verified }
      }.freeze

      def self.for(value, intent: nil)
        key = value.to_s.downcase.tr("-", "_").to_sym
        return key if SPECS.key?(key)

        case key
        when :low then :observe
        when :medium then :plan
        when :high then :repair
        when :critical then intent.to_sym == :write_repo_changes ? :repair : :deploy
        else :plan
        end
      rescue StandardError
        :plan
      end

      def self.spec(value)
        SPECS.fetch(for(value))
      end

      def self.capabilities(value)
        Master::Core::Capabilities.for(spec(value)[:profile])
      end

      def self.assess(goal, root: Master::ROOT)
        assessment = Master::CLI::FoldRisk.assess(goal, root:)
        mode = for(assessment[:risk], intent: assessment[:intent])
        spec = SPECS.fetch(mode)
        {
          mode: mode,
          risk: assessment[:risk],
          intent: assessment[:intent],
          model_tier: spec[:model_tier],
          council_required: spec[:council],
          evidence_contract: spec[:evidence]
        }
      end
    end
  end
end
