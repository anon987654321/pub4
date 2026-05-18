# frozen_string_literal: true

module Master
  module Ground
  class OrchestrationPolicy
    MODEL_TIERS = {
      cheap:        %i[low],
      fast:         %i[low medium],
      strong:       %i[high critical],
      local:        %i[low medium],
      browser_local: %i[low]
    }.freeze

    COUNCIL_TIERS = %i[high critical].freeze

    def initialize(router: IntentRouter.new, registry: nil)
      @router   = router
      @registry = registry
    end

    def evaluate(text)
      route    = @router.route(text)
      intent   = route[:intent]
      risk     = route[:risk]
      model    = select_model(risk)
      council  = COUNCIL_TIERS.include?(risk)
      {
        intent:       intent,
        risk:         risk,
        model_tier:   model,
        use_council:  council,
        evidence_req: council
      }
    end

    def model_for(risk)
      select_model(risk)
    end

    private

    def select_model(risk)
      case risk
      when :low      then :cheap
      when :medium   then :fast
      when :high     then :strong
      when :critical then :strong
      else                :fast
      end
    end
  end
  end
end
