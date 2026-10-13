# frozen_string_literal: true

require_relative "test_helper"

# A model the operator saved leads every chain, including the ones a one-shot
# instruction or a /fix pass builds. Only Session#run used to apply the pin, so
# the saved model never reached those runs.
class TestBootModelPin < Minitest::Test
  class FakeRouter
    attr_reader :probes

    def initialize(reachable:) = (@reachable = reachable; @probes = 0)

    def constrained_for(operation:) = "agy:gemini-3.8-flash-medium"

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

    attr_writer :chain

    def routed_chain(_message, task_type:) = @chain || %w[free/a free/b]
    def model = "free/a"
    attr_writer :local_only

    def local_only? = @local_only == true
    public :routed_models, :model_for
  end

  def test_homeostat_cheap_bias_does_not_break_the_fallback_ladder
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "openai_compatible" => {} })
    chain = [
      "claude-cli:claude-sonnet-5-5",
      "openrouter/free-model:free",
      "web-chat:grok",
      "ollama:gemma3:4b",
    ]
    router.define_singleton_method(:fallback_chain) { |task_type:| chain }
    router.define_singleton_method(:tier_for_model) do |model|
      %w[openrouter/free-model:free ollama:gemma3:4b].include?(model) ? "cheap" : "strong"
    end
    router.define_singleton_method(:priority_fallback_order) do |models|
      models.each_with_index.sort_by do |model, index|
        rank = if model.start_with?("web-chat:")
                 3
               else
                 case Master::Io::LaneSelection.kind(model)
                 when :local then 4
                 when :paid_tail then 1
                 when :free then 2
                 else 0
                 end
               end
        [rank, index]
      end.map(&:first)
    end
    homeostat = Struct.new(:model_tier_bias).new(:cheap)
    probe = Class.new do
      include Master::Review::Agent::ModelSelector

      def initialize(router:, homeostat:)
        @model_router = router
        @homeostat = homeostat
        @config = { "model" => "claude-cli:claude-sonnet-5-5" }
      end

      public :routed_chain
    end.new(router:, homeostat:)

    assert_equal chain, probe.routed_chain(nil, task_type: :exploration)
  end

  def test_a_saved_model_leads_the_chain_without_the_session
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: true))

    assert_equal %w[claude-cli:claude-sonnet-5-5 free/a free/b], agent.routed_models
  end

  def test_an_unreachable_saved_model_leaves_the_pool_order_alone
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: false))

    assert_equal %w[free/a free/b], agent.routed_models
  end

  # ask(..., operation:) takes this path, which is the one /fix's semantic laws and
  # the council use. A saved model is a preference, not a pin: availability and the
  # operation's own constraint choose the lane, so a saved sonnet never forces every
  # /fix call onto sonnet.
  def test_an_operation_call_is_chosen_by_availability_not_the_saved_model
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: true))

    assert_equal "agy:gemini-3.8-flash-medium", agent.model_for(operation: :semantic_law)
  end

  def test_an_explicit_model_choice_pins_the_operation_call
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: true))
    agent.model = "claude-cli:claude-opus-5-5"

    assert_equal "claude-cli:claude-opus-5-5", agent.model_for(operation: :semantic_law)
  end

  def test_a_saved_free_model_never_leads_a_live_subscription_chain
    agent = FakeAgent.new(saved: "nvidia/nemotron-3-super-120b-a12b:free", router: FakeRouter.new(reachable: true))
    agent.chain = %w[claude-cli:claude-opus-5-5 deepseek-chat]

    assert_equal %w[claude-cli:claude-opus-5-5 deepseek-chat], agent.routed_models
  end

  def test_a_saved_cloud_model_is_never_pinned_in_local_only_mode
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router: FakeRouter.new(reachable: true))
    agent.local_only = true

    assert_equal %w[free/a free/b], agent.routed_models
    assert_equal "agy:gemini-3.8-flash-medium", agent.model_for(operation: :semantic_law)
  end

  def test_the_reachability_probe_runs_once_per_agent
    router = FakeRouter.new(reachable: false)
    agent = FakeAgent.new(saved: "claude-cli:claude-sonnet-5-5", router:)
    3.times { agent.routed_models }

    assert_equal 1, router.probes
  end
end
