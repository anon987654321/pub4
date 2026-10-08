# frozen_string_literal: true

module Master
  module Ground
    module Policy
      class Orchestration
        MODEL_TIERS = {
          cheap: %i[low],
          fast: %i[low medium],
          strong: %i[high critical],
          local: %i[low medium],
          browser_local: %i[low],
        }.freeze

        COUNCIL_TIERS = %i[high critical].freeze

        COUNCIL_ROLES = {
          "Security" => %i[auth secrets tool_execution permission_changes],
          "Reliability" => %i[network provider runtime fallback],
          "Maintainer" => %i[code_mutation refactor file_deletion],
          "Architect" => %i[system_shape migration design],
          "User Advocate" => %i[ui mobile accessibility],
          "Accessibility" => %i[ui mobile accessibility],
          "Music Producer" => %i[sonic visual_rhythm pacing],
          "Hip-Hop Producer" => %i[sonic visual_rhythm pacing],
        }.freeze

        # Required output sections for high/critical risk responses.
        EVIDENCE_CONTRACT = %i[observed_facts inferred_plan uncertainty rollback_path verification_path].freeze

        def initialize(router: Master::CLI::IntentRouter.new, registry: nil)
          @router = router
          @registry = registry
        end

        def evaluate(text)
          route = @router.route(text)
          intent = route[:intent]
          risk = route[:risk]
          mode = Master::Operator::Mode.for(risk, intent:)
          spec = Master::Operator::Mode.spec(mode)
          {
            intent:,
            risk:,
            mode:,
            model_tier: spec[:model_tier],
            use_council: spec[:council],
            council_roles: spec[:council] ? roles_for(intent) : [],
            evidence_req: spec[:council],
            evidence_fields: spec[:council] ? EVIDENCE_CONTRACT : [],
          }
        end

        def roles_for(intent)
          domain = intent_domain(intent)
          COUNCIL_ROLES.filter_map { |persona, domains| persona if domains.include?(domain) }
        end

        private

        def intent_domain(intent)
          case intent
          when :wire_existing_module, :verify_patch_landed, :write_repo_changes then :code_mutation
          when :delete_redundant_config then :file_deletion
          when :run_ui_review then :ui
          when :run_sound_review then :sonic
          when :codify_policy, :refactor_to_ruby then :refactor
          else :general
          end
        end
      end
    end
  end
end
