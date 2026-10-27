# frozen_string_literal: true

require "test_helper"
require_relative "support_fake_config"
require_relative "support_council_answer"
require "tmpdir"
require "fileutils"
require_relative "../lib/fix/fix_loop"

# /fix runs in a temporary checkout that holds none of the gitignored
# MASTER/.master state: no config.yml, no lane_quota.yml. Every model call of
# one such run went to a free nemotron and later a 3B local model while a
# signed-in claude-cli sat first in the pool, because ComputePool read no
# models.yml rows for the real MASTER root and so ranked every lane without a
# catalogue row (claude-cli, grok-cli) out of the chain. These tests build the
# real router over the real root with a fresh state directory, agy dead, an
# OpenRouter key set and stub claude/grok binaries, and none of the support
# isolation that replaces the pool's rank.
class TestFixFreshCheckoutModels < Minitest::Test
  Selection = Master::Io::LaneSelection
  Quota = Master::Io::LaneQuota
  OPUS = "claude-cli:claude-opus-5-5"
  GROK = "grok-cli:auto"
  AGY_REPLY = "agy: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 165h22m49s."
  ENV_KEYS = %w[PATH OPENROUTER_API_KEY MASTER_MODEL MASTER_NO_CLAUDE_CLI MASTER_NO_GROK_CLI MASTER_NO_AGY_CLI MASTER_NO_OLLAMA MASTER_NO_POOL_PROBES].freeze

  def setup
    @saved = ENV_KEYS.to_h { |key| [key, ENV[key]] }
    @dir = Dir.mktmpdir("fresh-checkout")
    bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(bin)
    %w[claude grok].each do |name|
      path = File.join(bin, name)
      File.write(path, "#!/bin/sh\necho ok\n")
      File.chmod(0o755, path)
    end
    ENV["PATH"] = "#{bin}#{File::PATH_SEPARATOR}#{@saved.fetch("PATH")}"
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{"a" * 64}"
    %w[MASTER_MODEL MASTER_NO_CLAUDE_CLI MASTER_NO_GROK_CLI MASTER_NO_AGY_CLI].each { |key| ENV.delete(key) }
    ENV["MASTER_NO_OLLAMA"] = "1"
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.note("agy:auto", AGY_REPLY)
    @router = Master::CLI::Routing::ModelRouter.new(config: Master::TestSupport::FakeConfig.new(model: "nvidia/nemotron-3-super-120b-a12b:free"), root: Master::ROOT)
  end

  def teardown
    Quota.path = nil
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    FileUtils.remove_entry(@dir)
  end

  def test_the_real_pool_ranking_keeps_the_subscription_lanes
    pool = Master::CLI::Routing::ComputePool.new(router: @router, root: Master::ROOT)

    assert_equal [OPUS, GROK], pool.rank([GROK, OPUS]), "a lane with a models.yml row is ranked, not dropped"
  end

  def test_the_chain_leads_with_claude_then_grok_then_the_apis_and_ends_free
    chain = @router.fallback_chain(task_type: :code_generation)

    assert_equal OPUS, chain.first
    assert_equal :free, Selection.kind(chain.last), "free models close the chain"
    assert_empty chain.grep(/\Aagy:/), "the quota-dead agy lane is gone from the first call"
  end

  def test_fix_lane_probe_uses_the_code_generation_chain_not_the_agents_general_default
    calls = []
    candidates = [OPUS, "nvidia/nemotron-3-super-120b-a12b:free"]
    agent = Object.new
    agent.define_singleton_method(:candidate_models) do |message = nil, task_type: nil|
      calls << [message, task_type]
      candidates
    end
    agent.define_singleton_method(:ask_once) { |*| "OK" }
    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.instance_variable_set(:@agent, agent)
    captured_models = nil
    proof_mode = ENV.delete("MASTER_IN_PROOF")

    Master::Fix::LaneProbe.stub(:enabled?, true) do
      Selection.stub(:alive?, ->(_model) { true }) do
        Master::Fix::LaneProbe.stub(:run, ->(models:, ask:) { captured_models = models; [] }) do
          runner.send(:probe_lanes_once)
        end
      end
    end

    assert_equal [[nil, :code_generation]], calls
    assert_equal candidates, captured_models
  ensure
    proof_mode.nil? ? ENV.delete("MASTER_IN_PROOF") : ENV["MASTER_IN_PROOF"] = proof_mode
  end

  def test_fix_lane_probe_uses_the_live_catalogue_if_no_repair_candidate_is_usable
    calls = []
    agent = Object.new
    agent.define_singleton_method(:candidate_models) do |message = nil, task_type: nil|
      calls << [message, task_type]
      ["unavailable-provider:model"]
    end
    agent.define_singleton_method(:ask_once) { |*| "OK" }
    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.instance_variable_set(:@agent, agent)
    captured_models = nil
    proof_mode = ENV.delete("MASTER_IN_PROOF")

    alive = ->(model) { model == OPUS }
    Master::Fix::LaneProbe.stub(:enabled?, true) do
      Selection.stub(:alive?, alive) do
        Selection.stub(:catalogue, [OPUS, GROK]) do
          Master::Fix::LaneProbe.stub(:run, ->(models:, ask:) { captured_models = models; [] }) do
            runner.send(:probe_lanes_once)
          end
        end
      end
    end

    assert_equal [[nil, :code_generation]], calls
    assert_equal [OPUS], captured_models
  ensure
    proof_mode.nil? ? ENV.delete("MASTER_IN_PROOF") : ENV["MASTER_IN_PROOF"] = proof_mode
  end

  def test_every_operation_resolves_to_a_live_subscription_lane
    %i[file_write code_generation architecture scan_semantic restructure semantic_law].each do |operation|
      assert_equal OPUS, @router.constrained_for(operation:), "#{operation} left the live pool"
    end
  end

  # Short advisory calls lead with sonnet (quality .95, speed .85); the order comes
  # from the fast tier and the operation routes in data/models.yml, not from Ruby.
  def test_advisory_operations_lead_with_sonnet_and_edits_with_opus
    sonnet = "claude-cli:claude-sonnet-5-5"
    %i[council name_review scan_comment_drift scan_semantic_violations scan_semantic_opportunities
       scan_adversarial].each do |operation|
      assert_equal sonnet, @router.constrained_for(operation:), operation.to_s
    end
    assert_equal sonnet, @router.fallback_chain(task_type: :review).first
    assert_equal OPUS, @router.fallback_chain(task_type: :code_generation).first
    assert_equal OPUS, @router.constrained_for(operation: :file_write)
  end

  def test_the_agent_model_for_never_names_a_free_or_local_lane_while_claude_is_live
    agent = Class.new do
      include Master::Review::Agent::ModelOverride
      include Master::Review::Agent::ModelSelector

      def initialize(router) = (@model_router = router; @config = { "model" => "nvidia/nemotron-3-super-120b-a12b:free" }; @bus = nil)
      def local_only? = false
      def routed_chain(_message, task_type:) = @model_router.fallback_chain(task_type: :code_generation)
      public :routed_models, :model_for
    end.new(@router)

    assert_equal OPUS, agent.routed_models.first
    %i[code_generation file_write semantic_law name_review].each do |operation|
      assert_match(/\Aclaude-cli:/, agent.model_for(operation:), operation.to_s)
    end
  end

  def test_the_boot_default_is_the_first_live_lane_not_agy_and_not_the_free_primary
    assert_equal OPUS, Master.default_model
  end

  def test_the_council_personas_resolve_to_live_non_free_lanes
    chain = @router.fallback_chain(task_type: :review)
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
    agent = CountingAgent.new(chain)
    delib = Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)

    personas.each { |persona| delib.send(:ask_persona, persona:, code: "x = 1", context: nil) }

    assert_equal [OPUS] * 4, agent.asked, "the panel is spread over the live subscription lanes, not the metered APIs"
    assert(agent.asked.none? { |id| Selection::FREE_CLASS_KINDS.include?(Selection.kind(id)) })
  end

  # A pin is the only lane. With MASTER_MODEL_STRICT=0 it is the first choice instead:
  # the dispatcher door sends the pinned lane while it is live and gives the call back
  # to the router's lane when the pin is quota-dead or has just failed, so a failover
  # hop is not routed back onto the lane that failed.
  def test_a_strict_pin_is_asked_even_after_its_lane_failed
    ENV["MASTER_MODEL"] = OPUS
    Master::Io::ModelSkipCache.skip!(OPUS, reason: "claude exited 1")

    assert_equal OPUS, Master::Review::LLMDispatcher.allocate.send(:answering_model, GROK, nil)
  ensure
    Master::Io::ModelSkipCache.clear!
  end

  def test_a_pinned_lane_yields_to_the_next_live_lane_only_when_failover_is_asked_for
    ENV["MASTER_MODEL"] = OPUS
    ENV["MASTER_MODEL_STRICT"] = "0"
    door = Master::Review::LLMDispatcher.allocate
    asked = []
    answer = ->(selected) { door.send(:answering_model, selected, nil).tap { |m| asked << m } }

    assert_equal OPUS, answer.call(GROK), "the pin is the first choice"

    Master::Io::ModelSkipCache.skip!(OPUS, reason: "claude exited 1")
    assert_equal GROK, answer.call(GROK), "after an error the failover hop is not sent back to the pin"
    Master::Io::ModelSkipCache.clear!

    Quota.note(OPUS, "You've hit your session limit - resets 5pm (Europe/Oslo)")
    assert_equal GROK, answer.call(GROK), "a quota-dead pin yields"
    assert_equal [OPUS, GROK, GROK], asked
  ensure
    ENV.delete("MASTER_MODEL_STRICT")
    Master::Io::ModelSkipCache.clear!
  end


  def test_a_saved_model_in_the_default_config_does_not_pin_the_boot
    ENV["MASTER_MODEL"] = nil
    assert_equal [OPUS, "availability"], Selection.boot_choice(env: ENV, saved: nil)
    assert_equal [GROK, "MASTER_MODEL"], Selection.boot_choice(env: { "MASTER_MODEL" => GROK }, saved: OPUS)
  end

  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  class CountingAgent
    attr_reader :asked

    def initialize(models) = (@models = models; @asked = [])
    def candidate_models(_message = nil, task_type: nil) = @models
    def ask_once(_prompt, model: nil, **) = (@asked << model; CouncilAnswer.json)
    def ask(_prompt, **) = (@asked << :routed; CouncilAnswer.json)
  end
end
