# frozen_string_literal: true

module Master
  module Core
    module Protocol
      # CapabilityContract ensures that MASTER never performs an action 
      # that the host application (Rails) has not explicitly permitted.
      class CapabilityContract
        def initialize(capabilities)
          @capabilities = capabilities # e.g., ["draft_post", "search_marketplace"]
        end

        def permitted?(action)
          @capabilities.include?(action.to_s)
        end

        def suggest_alternative(action)
          # If an action is forbidden, suggest the closest permitted equivalent
          # based on a mapping of internal intents to surface capabilities.
          nil 
        end
      end
    end
  end
end
