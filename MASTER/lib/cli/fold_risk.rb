# frozen_string_literal: true

require_relative "intent_router"
require_relative "../ground/host_budget"

module Master
  module CLI
    # FoldRisk — classify goal risk for conditional ideation and council checks.
    module FoldRisk
      HIGH_PATTERNS = /\b(commit|ship|push|deploy|tribunal|full\s+pass|refactor\s+all|delete\s+all)\b/i.freeze
      # A goal that starts a process or session executes, and only the repair profile may
      # execute: classified low it ran in observe and every exec was refused by capability.
      EXEC_PATTERNS = /\b(create|start|launch|spawn|open|run|attach)\b.{0,40}\b(terminal|pty|shell|screen|tmux|session|process|server|daemon|command|script)\b/i.freeze
      MEDIUM_PATTERNS = /\b(fix|implement|add|migrate|workflow|scan|refactor|clean|polish)\b/i.freeze
      REPOSITORY_DELIVERY_INTENTS = %i[
        write_repo_changes run_full_workflow run_rails_through run_master_through
        design_frontend refactor_rails_app redesign_mobile_pwa generate_rails_pwa
        codify_policy wire_existing_module create_facade refactor_to_ruby apply_user_style_rules
      ].freeze

      module_function

      # One bounded task grant for repository repair only. It never grants
      # external publication, remote deploy, spending, messaging or host mutation.
      def repository_delivery_authorized?(intent, mode:)
        mode.to_s.downcase.to_sym == :repair &&
          REPOSITORY_DELIVERY_INTENTS.include?(intent.to_s.downcase.to_sym)
      end

      def assess(goal, root: Dir.pwd)
        route = CLI::IntentRouter.new.route(goal)
        risk = route[:risk]
        risk = :high if goal.to_s.match?(HIGH_PATTERNS)
        risk = :high if goal.to_s.match?(EXEC_PATTERNS)
        risk = :medium if risk == :low && goal.to_s.match?(MEDIUM_PATTERNS)
        risk = :high if repo_wide?(goal)
        risk = bump_risk(risk, route[:intent])
        { risk:, intent: route[:intent] }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "FoldRisk.assess")
        { risk: :critical, intent: :unknown }
      end

      def ideation_required?(risk) = %i[medium high critical].include?(risk.to_sym)
      def council_required?(risk) = %i[high critical].include?(risk.to_sym)

      def bump_risk(risk, intent)
        return :critical if intent == :delete_redundant_config
        return :high if %i[
          write_repo_changes run_full_workflow run_rails_through run_master_through
          design_frontend refactor_rails_app redesign_mobile_pwa generate_rails_pwa
        ].include?(intent) && risk != :critical

        risk
      end

      def repo_wide?(goal)
        Ground::HostBudget.repo_wide_request?(goal.to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "FoldRisk.repo_wide?")
        raise "repo-wide risk policy unreadable: #{e.class}: #{e.message}"
      end
    end
  end
end
