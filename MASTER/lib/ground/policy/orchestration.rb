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

        def initialize(router: IntentRouter.new, registry: nil)
          @router   = router
          @registry = registry
        end

        def evaluate(text)
          route = @router.route(text)
          intent = route[:intent]
          risk = route[:risk]
          model = select_model(risk)
          council = COUNCIL_TIERS.include?(risk)
          {
            intent:,
            risk:,
            model_tier: model,
            use_council: council,
            council_roles: council ? roles_for(intent) : [],
            evidence_req: council,
            evidence_fields: council ? EVIDENCE_CONTRACT : [],
          }
        end

        def model_for(risk)
          select_model(risk)
        end

        def roles_for(intent)
          domain = intent_domain(intent)
          COUNCIL_ROLES.filter_map { |persona, domains| persona if domains.include?(domain) }
        end

        private

        def select_model(risk)
          case risk
          when :low      then :cheap
          when :medium   then :fast
          when :high, :critical then :strong
          else :fast
          end
        end

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
