# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "support_council_answer"

# One rule picks the model for every /fix and council call: the tier's models in
# data/models.yml order, dead lanes dropped (quota, silence, the hand-kept list),
# free models last. Each test that claims the rule is reached counts the calls
# that arrive at it, so a green run cannot mean the code sits unused.
class TestLaneSelection < Minitest::Test
  Selection = Master::Io::LaneSelection
  Quota = Master::Io::LaneQuota

  OPUS = "claude-cli:claude-opus-5-5"
  SONNET = "claude-cli:claude-sonnet-5-5"
  GROK = "grok-cli:auto"
  AGY = "agy:auto"
  LOCAL = "ollama:gemma3:4b"
  NEMOTRON = "nvidia/nemotron-3-super-120b-a12b:free"
  NANO = "nvidia/nemotron-3.5-lightning:free"

  # models.yml is parsed once per change and handed out frozen; an edit is seen on the next read.
  def test_the_models_file_is_read_again_only_when_it_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "models.yml")
      File.write(path, "models:\n  default:\n    - id: a\n")
      first = Selection.config(path)

      assert_same first, Selection.config(path)
      assert_predicate first.dig("models", "default"), :frozen?

      File.write(path, "models:\n  default:\n    - id: a\n    - id: b\n")
      assert_equal %w[a b], Selection.tier("default", cfg: Selection.config(path))
    end
  end
  DEEPSEEK = "deepseek-chat"
  AGY_REPLY = "agy: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 165h22m49s."
  CLAUDE_REPLY = "You've hit your session limit · resets 5pm (Europe/Oslo)"
  ALL = ->(_model) { true }
  NOON = Time.utc(2026, 10, 11, 12, 0, 0).to_f

  def setup
    @dir = Dir.mktmpdir
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.clock = -> { NOON }
  end

  def teardown
    Quota.path = nil
    Quota.clock = -> { Time.now.to_f }
    FileUtils.remove_entry(@dir)
  end

  # Counts every call that reaches the selection function while the block runs.
  def counting(method_name)
    calls = []
    original = Selection.method(method_name)
    Selection.define_singleton_method(method_name) { |*args, **kw, &blk| calls << args; original.call(*args, **kw, &blk) }
    yield calls
  ensure
    Selection.singleton_class.send(:remove_method, method_name)
  end

  def test_first_live_of_the_tier_skips_a_quota_dead_lane
    tier = [AGY, OPUS, GROK, NEMOTRON]
    assert_equal OPUS, Selection.first_live(tier), "claude-cli leads the subscription lanes whatever order the list came in"

    Quota.note(AGY, AGY_REPLY)
    assert_equal OPUS, Selection.first_live(tier)

    Quota.note(OPUS, CLAUDE_REPLY)
    assert_equal GROK, Selection.first_live(tier)
  end

  def test_the_real_default_tier_leads_with_opus_and_ends_free_models_last
    tier = Selection.tier("default")
    assert_equal OPUS, tier.first
    assert_equal OPUS, Selection.first_live(tier)

    Quota.note(OPUS, CLAUDE_REPLY)
    assert_equal AGY, Selection.first_live(tier), "the claude-cli lane is dead as a whole, sonnet with opus"
    ordered = Selection.order(tier)
    kinds = ordered.map { |id| Selection.kind(id) }
    assert_equal kinds.sort_by { |k| Selection::KIND_RANK.fetch(k) }, kinds, "remote, then local, then free"
  end

  def test_free_models_come_last_whatever_the_given_order
    mixed = [NEMOTRON, NANO, LOCAL, DEEPSEEK, GROK]
    assert_equal [GROK, DEEPSEEK, LOCAL, NEMOTRON, NANO], Selection.order(mixed), "a subscription CLI precedes a metered API key"
    assert_equal [NEMOTRON, NANO, LOCAL, DEEPSEEK, GROK], Selection.order(mixed, free_last: false), "a free route keeps its order"
  end

  def test_subscription_lanes_lead_in_claude_grok_agy_order_ahead_of_api_keys
    assert_equal [OPUS, GROK, AGY, DEEPSEEK, LOCAL, NEMOTRON], Selection.order([NEMOTRON, DEEPSEEK, AGY, GROK, LOCAL, OPUS])
  end

  def test_browser_websites_have_independent_provider_identity
    assert_equal "web-chat:grok", Selection.provider("web-chat:grok")
    assert_equal "web-chat:chatgpt", Selection.provider("web-chat:chatgpt")
    refute_equal Selection.provider("web-chat:grok"), Selection.provider("web-chat:chatgpt")
  end

  def test_the_boot_choice_is_the_first_live_lane_and_names_its_source
    assert_equal [OPUS, "availability"], Selection.boot_choice(env: {}, saved: nil, alive: ALL)
    assert_equal [AGY, "MASTER_MODEL"], Selection.boot_choice(env: { "MASTER_MODEL" => AGY }, saved: nil, alive: ALL)

    sonnet = "claude-cli:claude-sonnet-5-5"
    assert_equal [sonnet, "saved preference"], Selection.boot_choice(env: {}, saved: sonnet, alive: ALL)
    assert_equal [OPUS, "availability"], Selection.boot_choice(env: {}, saved: NEMOTRON, alive: ALL), "a saved free model never leads a live subscription"

    Quota.note(OPUS, CLAUDE_REPLY)
    assert_equal [GROK, "availability"], Selection.boot_choice(env: {}, saved: sonnet, alive: ALL), "a dead preference is not tried"
  end

  def test_the_primary_report_names_the_lane_and_why
    Quota.note(AGY, AGY_REPLY)
    assert_match(/\Aprimary: #{Regexp.escape(OPUS)} \(first live lane by availability.*; dead: agy/, Selection.primary_report(env: {}, alive: ALL))
    assert_match(/pinned \(MASTER_MODEL\), no failover/,
                 Selection.primary_report(env: { "MASTER_MODEL" => GROK }, alive: ALL))
    assert_match(/pinned \(MASTER_MODEL\), failover on/,
                 Selection.primary_report(env: { "MASTER_MODEL" => GROK, "MASTER_MODEL_STRICT" => "0" }, alive: ALL))
  end

  def test_a_free_class_lane_warns_once_while_a_live_lane_exists
    Selection.watch_free_class!
    warning = Selection.free_class_warning(NEMOTRON, :file_write, alive: ALL)
    assert_match(/WARNING free-class lane #{Regexp.escape(NEMOTRON)} used for file_write while claude-cli:claude-opus-5-5 is live/, warning)
    assert_nil Selection.free_class_warning(NEMOTRON, :file_write, alive: ALL), "once per lane"
    assert_nil Selection.free_class_warning(OPUS, :file_write, alive: ALL), "a subscription lane never warns"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_a_lane_probe_on_a_free_lane_is_not_a_warning
    Selection.watch_free_class!

    assert_nil Selection.free_class_warning(NEMOTRON, :lane_probe, alive: ALL)
    refute_nil Selection.free_class_warning(NEMOTRON, :structural_review, alive: ALL), "the probe used up no warning"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_when_every_lane_is_dead_the_list_comes_back_for_the_typed_offline
    lanes = [AGY, OPUS]
    Quota.note(AGY, AGY_REPLY)
    Quota.note(OPUS, CLAUDE_REPLY)
    assert_empty Selection.order(lanes)
    assert_nil Selection.first_live(lanes)
    assert_equal lanes, Selection.order_or_all(lanes)
  end

  def test_the_always_online_tail_answers_when_every_remote_lane_is_dead
    models = Selection.catalogue
    models.map { |m| Quota.lane_of(m) }.uniq.reject { |lane| lane == "ollama" }.each { |lane| Quota.note("#{lane}:x", CLAUDE_REPLY) }

    live = Selection.order(models)
    refute_empty live
    assert Master::Io::LaneHealth.local_model?(live.first), "a local model leads: #{live}"
    assert(live.none? { |m| Selection.kind(m) == :remote }, "no remote model is left: #{live}")
    assert_match(/\Aonline: yes via ollama:/, Master::Io::LaneHealth.line(models, refuses: ->(m) { Quota.dead?(m) }))
  end

  def test_personas_spread_across_live_providers_and_never_to_free_while_a_lane_lives
    Quota.note(AGY, AGY_REPLY)
    candidates = [AGY, NEMOTRON, OPUS, SONNET, NANO, GROK, DEEPSEEK, LOCAL]
    names = %w[A B C D E F]

    lanes = Selection.spread(names, candidates)

    assert_equal [OPUS, GROK, OPUS, GROK, OPUS, GROK], lanes.values
    assert(lanes.values.none? { |m| Selection.kind(m) == :free }, "no free model while a live lane exists")
    refute_includes lanes.values, AGY
  end

  def test_one_live_provider_is_reused_and_free_is_the_last_resort
    assert_equal({ "A" => OPUS, "B" => OPUS }, Selection.spread(%w[A B], [OPUS, SONNET, NEMOTRON]))
    assert_equal({ "A" => NEMOTRON, "B" => NEMOTRON }, Selection.spread(%w[A B], [NEMOTRON, NANO]))
    assert_equal({ "A" => nil }, Selection.spread(%w[A], []))
  end

  # A counting agent with the real provider spellings: nothing is called that the
  # selection did not hand it, and the free nemotron lanes are never asked.
  class CountingAgent
    attr_reader :asked, :candidate_calls

    def initialize(models)
      @models = models
      @asked = []
      @candidate_calls = 0
    end

    def candidate_models(_message = nil, task_type: nil)
      @candidate_calls += 1
      @task = task_type
      @models
    end

    attr_reader :task

    def ask_once(_prompt, model: nil, **)
      @asked << model
      CouncilAnswer.json
    end

    def ask(_prompt, **)
      @asked << :routed
      CouncilAnswer.json
    end
  end

  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  def test_the_council_reaches_the_selection_and_skips_dead_and_free_lanes
    Quota.note(AGY, AGY_REPLY)
    agent = CountingAgent.new([AGY, NEMOTRON, OPUS, GROK, NANO, LOCAL])
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
    delib = Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)

    counting(:spread) do |calls|
      personas.each { |persona| delib.send(:ask_persona, persona:, code: "x = 1", context: nil) }
      refute_empty calls, "ask_persona never reached LaneSelection.spread"
    end

    assert_equal [OPUS, GROK, OPUS, GROK], agent.asked
    assert_equal :review, agent.task
    assert_equal 1, agent.candidate_calls, "the lane list is read once per council"
  end

  def test_a_critique_panel_reaches_the_selection
    Quota.note(AGY, AGY_REPLY)
    agent = CountingAgent.new([AGY, OPUS, NEMOTRON, GROK])
    critique = Master::Review::Council::Critique.new(mode: :general, agent:, files: [__FILE__])

    counting(:spread) do |calls|
      critique.run
      refute_empty calls, "Critique#run never reached LaneSelection.spread"
    end

    refute_empty agent.asked
    named = agent.asked.compact - [:routed]
    refute_empty named, "no persona was given a lane"
    assert(named.all? { |m| [OPUS, GROK].include?(m) }, "asked: #{agent.asked.tally}")
  end

  # A real router with its probes and telemetry replaced by pass-throughs, so the
  # chain it returns is what the selection made of the chain it was given.
  def router_over(chain, tier_rows)
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "routes" => { "code_generation" => "default", "chitchat" => "free", "exploration" => "free" },
                                            "models" => { "default" => tier_rows.map { |id| { "id" => id } }, "free" => tier_rows.map { |id| { "id" => id } } } })
    passthrough = Object.new.tap do |o|
      o.define_singleton_method(:rank) { |ids, **| ids }
      o.define_singleton_method(:select) { |ids, **| ids.first }
    end
    router.instance_variable_set(:@compute_pool, passthrough)
    router.instance_variable_set(:@provider_health, passthrough)
    router.instance_variable_set(:@capability_map, Object.new.tap { |o| o.define_singleton_method(:best_model_for) { |_| nil } })
    router.define_singleton_method(:chain_for) { |_task| chain }
    router.define_singleton_method(:reachable?) { |_id| true }
    router.define_singleton_method(:recently_failed?) { |_id| false }
    router.define_singleton_method(:healthy) { |models| models }
    router.define_singleton_method(:prefer_floor) { |all, _fresh, **| all }
    router
  end

  def test_the_router_chain_and_preferred_pass_through_the_selection
    Quota.note(AGY, AGY_REPLY)
    chain = [NEMOTRON, AGY, NANO, OPUS, GROK]
    router = router_over(chain, [NEMOTRON, AGY, OPUS])

    counting(:order_or_all) do |calls|
      assert_equal [OPUS, GROK, NEMOTRON, NANO], router.fallback_chain(task_type: :code_generation)
      refute_empty calls, "fallback_chain never reached LaneSelection"
    end
    counting(:best_class) do |calls|
      assert_equal OPUS, router.preferred(task_type: :code_generation)
      refute_empty calls, "preferred never reached LaneSelection"
    end
  end

  def test_a_free_route_still_falls_back_from_premium_before_free
    router = router_over([NEMOTRON, OPUS], [NEMOTRON, OPUS])
    assert_equal [OPUS, NEMOTRON], router.fallback_chain(task_type: :exploration)
    assert_equal NEMOTRON, router.preferred(task_type: :exploration)
  end
  Config = Struct.new(:task_type, :model, :reasoning_mode, keyword_init: true)

  # The fix loop asks through the real Agent: ask -> routed chain -> router ->
  # LaneSelection. The dispatcher is a counting stub that records which model the
  # request was addressed to, in the real provider spellings.
  def test_the_repair_loop_request_reaches_the_selection_and_lands_on_the_first_live_lane
    Quota.note(AGY, AGY_REPLY)
    router = router_over([NEMOTRON, AGY, OPUS, GROK, NANO], [NEMOTRON, AGY, OPUS])
    sent = []
    dispatcher = Object.new
    dispatcher.define_singleton_method(:send_with_cache) { |model, *_a, **_k| sent << model; Master::Result.ok("fixed") }
    agent = Master::Review::Agent.allocate
    agent.instance_variable_set(:@model_router, router)
    agent.instance_variable_set(:@dispatcher, dispatcher)
    agent.instance_variable_set(:@config, Config.new(task_type: "code_generation", model: OPUS))
    agent.instance_variable_set(:@bus, nil)
    law = Struct.new(:id, :severity).new("TEST_RULE", :warning)
    loop = Master::Fix::RepairLoop.new(law:, agent:, scanner: Object.new, root: Master::ROOT, bus: nil)

    counting(:order_or_all) do |calls|
      assert_equal "fixed", loop.send(:ask_agent, "repair this")
      refute_empty calls, "the repair loop's ask never reached LaneSelection"
    end

    assert_equal [OPUS], sent, "the first live lane of the tier, not the dead agy and not a free nemotron"
  end

  # A launch script whose PATH leaves out ~/.local/bin, where the installer puts claude, still finds it there.
  def test_claude_outside_path_is_found_in_the_user_bin
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\n")
      File.chmod(0o755, File.join(bin, "claude"))
      found, missing = with_path("/usr/bin:/bin") do
        [Master::Io::Exec.cli_binary("claude", user_bins: [bin]), Master::Io::Exec.cli_binary("claude", user_bins: [])]
      end

      assert_equal [File.join(bin, "claude"), nil], [found, missing]
    end
  end

  def with_path(path)
    previous = ENV.fetch("PATH")
    ENV["PATH"] = path
    yield
  ensure
    ENV["PATH"] = previous
  end
end
