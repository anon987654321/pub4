# frozen_string_literal: true

require_relative "test_helper"

# A model the operator saved leads every chain, including the ones a one-shot
# instruction or a /fix pass builds. Only Session#run used to apply the pin, so
# the saved model never reached those runs.
class TestBootModelPin < Minitest::Test
  class FakeRouter
    attr_reader :probes

    def initialize(reachable:) = (@reachable = reachable; @probes = 0)

    def unreachable_reason(_model, wait: false)
      @probes += 1
      @reachable ? nil : "down"
    end
  end

  class FakeAgent
    include Master::Review::Agent::ModelOverride
    include Master::Review::Agent::ModelSelector

    def initialize(saved:, router:)
      @config = { "model" => saved }
      @model_router = router
      @bus = nil
    end

    def routed_chain(_message, task_type:) = %w[free/a free/b]
    public :routed_models
  end

  def test_a_saved_model_leads_the_chain_without_the_session
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: true))

    assert_equal %w[claude-cli:claude-sonnet-5-5 free/a free/b], agent.routed_models
  end

  def test_an_unreachable_saved_model_leaves_the_pool_order_alone
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: false))

    assert_equal %w[free/a free/b], agent.routed_models
  end

  def test_the_reachability_probe_runs_once_per_agent
    router = FakeRouter.new(reachable: false)
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router:)
    3.times { agent.routed_models }

    assert_equal 1, router.probes
  end
end
