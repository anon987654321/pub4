# frozen_string_literal: true

# No dependencies: the gate kernel under gates/ loads this file without the runtime.
module Master
  # What a flat "inconclusive" or "offline" leaves out: whether the question
  # answers itself, what asking it costs, and whose call the answer is. Each
  # field has a reader. `decidability` is what /fix branches on (a
  # :decision_for_operator gap is listed, never attempted); all three print in
  # one clause through Trace::Dmesg.gap and the gate renderer.
  #
  #   horizon        :never (this environment cannot), :operator (waits for a
  #                  person to act), or seconds-from-now when it resolves alone
  #   cost_to_check  :seconds, :minutes, :deploy_host or :operator
  #   decidability   :fact (measuring settles it) or :decision_for_operator
  #                  (a rendered value or a baseline: no measurement settles it)
  Gap = Data.define(:horizon, :cost_to_check, :decidability) do
    def initialize(horizon: :never, cost_to_check: :operator, decidability: :fact)
      raise ArgumentError, "horizon: #{horizon.inspect}" unless %i[never operator].include?(horizon) || (horizon.is_a?(Numeric) && horizon.positive?)
      raise ArgumentError, "cost_to_check: #{cost_to_check.inspect}" unless Gap::COSTS.key?(cost_to_check)
      raise ArgumentError, "decidability: #{decidability.inspect}" unless Gap::DECIDABILITIES.key?(decidability)

      super
    end

    def decision_for_operator? = decidability == :decision_for_operator

    # "gap: never resolves alone, checking costs a trip to the deploy host, a fact"
    def clause
      "gap: #{horizon_phrase}, checking costs #{Gap::COSTS.fetch(cost_to_check)}, #{Gap::DECIDABILITIES.fetch(decidability)}"
    end

    alias to_s clause

    private

    def horizon_phrase
      case horizon
      when :never then "never resolves alone"
      when :operator then "waits for the operator"
      else "resolves alone in #{horizon >= 60 ? "#{(horizon / 60.0).ceil}m" : "#{horizon.ceil}s"}"
      end
    end
  end

  # The recurring ones, so a site names the situation rather than restating it.
  class Gap
    COSTS = { seconds: "seconds", minutes: "minutes", deploy_host: "a trip to the deploy host", operator: "the operator" }.freeze
    DECIDABILITIES = { fact: "a fact", decision_for_operator: "the operator's decision" }.freeze

    NO_BROWSER = new(horizon: :never, cost_to_check: :minutes, decidability: :fact)
    DEPLOY_HOST_ONLY = new(horizon: :never, cost_to_check: :deploy_host, decidability: :fact)
    NEEDS_CAPTURE = new(horizon: :operator, cost_to_check: :minutes, decidability: :fact)
    OPERATOR_DECISION = new(horizon: :operator, cost_to_check: :operator, decidability: :decision_for_operator)
  end
end
