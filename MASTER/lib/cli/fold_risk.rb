# frozen_string_literal: true

require_relative "../ground/intent_router"
require_relative "../ground/host_budget"

module Master
  module CLI
    # FoldRisk — classify goal risk for conditional ideation and council gates.
    module FoldRisk
      HIGH_PATTERNS = /\b(commit|ship|push|deploy|tribunal|full\s+pass|refactor\s+all|delete\s+all)\b/i.freeze
      MEDIUM_PATTERNS = /\b(fix|implement|add|migrate|workflow|scan|refactor|clean|polish)\b/i.freeze

      module_function

      def assess(goal, root: Dir.pwd)
        route = Ground::IntentRouter.new.route(goal)
        risk = route[:risk]
        risk = :high if goal.to_s.match?(HIGH_PATTERNS)
        risk = :medium if risk == :low && goal.to_s.match?(MEDIUM_PATTERNS)
        risk = :high if repo_wide?(goal)
        risk = bump_risk(risk, route[:intent])
        { risk:, intent: route[:intent] }
      rescue StandardError
        { risk: :medium, intent: :unknown }
      end

      def ideation_required?(risk) = %i[medium high critical].include?(risk.to_sym)
      def council_required?(risk) = %i[high critical].include?(risk.to_sym)

      def bump_risk(risk, intent)
        return :critical if intent == :delete_redundant_config
        return :high if %i[write_repo_changes run_full_workflow].include?(intent) && risk != :critical

        risk
      end

      def repo_wide?(goal)
        Ground::HostBudget.repo_wide_request?(goal.to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "FoldRisk.repo_wide?")
        false
      end
    end
  end
end
