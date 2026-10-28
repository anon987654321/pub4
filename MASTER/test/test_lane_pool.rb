# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "sqlite3"
require "tmpdir"

# The pool behind the one selection rule: the fastest free model first, a capped
# paid tail between the live lanes and the free ones, and the lanes that read
# images first when a call carries one. Provider ids are the real spellings.
class TestLanePool < Minitest::Test
  Selection = Master::Io::LaneSelection
  Tail = Master::Io::PaidTail
  Quota = Master::Io::LaneQuota

  OPUS = "claude-cli:claude-opus-5-5"
  GROK = "grok-cli:auto"
  DEEPSEEK = "deepseek-chat"
  LOCAL = "ollama:gemma3:4b"
  SUPER = "nvidia/nemotron-3-super-120b-a12b:free"
  LIGHTNING = "nvidia/nemotron-3.5-lightning:free"
  ULTRA = "nvidia/nemotron-3-ultra-550b-a55b:free"
  GEMMA = "google/gemma-4-31b-it:free"
  HAIKU = "anthropic/claude-haiku-5.5"
  LUNA = "openai/gpt-6-luna"
  PRO = "openai/gpt-6-pro"
  FLASH = "google/gemini-2.5-flash"

  def setup
    @dir = Dir.mktmpdir
    @db = File.join(@dir, "catalog.sqlite3")
    build_catalog
    Quota.path = File.join(@dir, "lane_quota.yml")
    @saved_paid = ENV.delete("MASTER_PAID_TAIL")
    Tail.reset!
    db = @db
    Tail.define_singleton_method(:default_db) { db }
  end

  def teardown
    Tail.singleton_class.send(:remove_method, :default_db)
    Tail.reset!
    Quota.path = nil
    @saved_paid.nil? ? ENV.delete("MASTER_PAID_TAIL") : ENV["MASTER_PAID_TAIL"] = @saved_paid
    FileUtils.remove_entry(@dir)
  end

  def build_catalog
    db = SQLite3::Database.new(@db)
    db.execute("CREATE TABLE provider_models (source TEXT NOT NULL, id TEXT NOT NULL, name TEXT, description TEXT, context_length INTEGER, input_modalities TEXT, output_modalities TEXT, price_prompt REAL, price_completion REAL, tags TEXT, raw_json TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (source, id))")
    rows = [
      [HAIKU, "text,image", 8e-7, 2.4e-6], [LUNA, "text", 5e-7, 2e-6], [PRO, "text", 5e-6, 2e-5],
      [FLASH, "text,image", 3e-7, 2.5e-6], [GEMMA, "text,image", 0.0, 0.0], [SUPER, "text", 0.0, 0.0]
    ]
    rows.each do |id, input, prompt, completion|
      db.execute("INSERT INTO provider_models VALUES ('openrouter', ?, ?, '', 1000, ?, 'text', ?, ?, '', '{}', '2026-10-11')", [id, id, input, prompt, completion])
    end
  end

  def test_the_fastest_recently_answering_free_model_goes_first
    seconds = { LIGHTNING => 3.0, SUPER => 170.0, ULTRA => 20.0 }
    ordered = Selection.order([SUPER, GEMMA, ULTRA, LIGHTNING], latency: ->(id) { seconds[id] })

    assert_equal [LIGHTNING, ULTRA, GEMMA, SUPER], ordered, "unmeasured sits at the neutral prior, between fast and slow"
  end

  def test_the_router_hands_the_pools_measured_latency_to_the_selection
    pool = Object.new
    pool.define_singleton_method(:rank) { |ids, **| ids }
    pool.define_singleton_method(:latency_s) { |id| { LIGHTNING => 3.0, SUPER => 170.0 }[id] }
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "routes" => { "code_generation" => "default" }, "models" => {} })
    router.instance_variable_set(:@compute_pool, pool)
    router.instance_variable_set(:@provider_health, pool)
    router.define_singleton_method(:chain_for) { |_| [SUPER, LIGHTNING, OPUS] }
    router.define_singleton_method(:reachable?) { |_| true }
    router.define_singleton_method(:recently_failed?) { |_id| false }
    router.define_singleton_method(:prefer_floor) { |all, _f, **| all }

    assert_equal [OPUS, LIGHTNING, SUPER], router.fallback_chain(task_type: :code_generation)
  end

  def test_compute_pool_reports_a_measured_latency_and_marks_a_failing_model_slow
    pool = Master::CLI::Routing::ComputePool.allocate
    pool.instance_variable_set(:@mutex, Mutex.new)
    pool.instance_variable_set(:@stats, { LIGHTNING => { calls: 4, successes: 4, failures: 0, latency_ms: 3200.0 },
                                          SUPER => { calls: 2, successes: 0, failures: 2, latency_ms: 0.0 } })
    assert_in_delta 3.2, pool.latency_s(LIGHTNING)
    assert_equal Selection::SLOW_S, pool.latency_s(SUPER)
    assert_nil pool.latency_s(GEMMA)
  end

  def test_every_free_model_gets_the_short_timeout_even_after_a_fast_probe
    door = Master::Review::LLMDispatcher.allocate
    door.instance_variable_set(:@availability, Struct.new(:dispatch_deadline_s).new(300))
    router = Object.new
    router.define_singleton_method(:latency_s) { |id| id == LIGHTNING ? 3.0 : nil }
    door.instance_variable_set(:@model_router, router)

    assert_equal 60, door.send(:call_deadline_for, GEMMA), "unmeasured free lanes get the configured ceiling"
    assert_equal 60, door.send(:call_deadline_for, LIGHTNING), "a fast short probe does not predict large-prompt latency"
    assert_equal 300, door.send(:call_deadline_for, OPUS), "subscription calls retain the dispatcher deadline"
  end

  def test_the_paid_tail_lists_cheap_catalog_models_only
    assert_equal [HAIKU, LUNA], Tail.models, "free, over-cap and models.yml's own models are left out"
  end

  def test_the_paid_tail_sits_after_live_lanes_and_before_the_free_ones
    mixed = [SUPER, HAIKU, LOCAL, LUNA, DEEPSEEK, OPUS]
    assert_equal [OPUS, DEEPSEEK, HAIKU, LUNA, LOCAL, SUPER], Selection.order(mixed)
    assert_equal :paid_tail, Selection.kind(HAIKU)
  end

  def test_the_tail_turns_itself_off_at_the_run_cap_with_one_line
    lines = []
    Master::Trace::Dmesg.stub(:status, ->(unit, msg, **) { lines << "#{unit}: #{msg}" }) do
      Tail.spend!(HAIKU, 3.0)
      assert_includes Selection.order([OPUS, HAIKU]), HAIKU
      Tail.spend!(LUNA, 2.5)
      Tail.spend!(HAIKU, 1.0)
      Tail.spend!(OPUS, 99.0)
    end

    assert_equal [OPUS], Selection.order([OPUS, HAIKU, LUNA])
    assert_empty Tail.models
    assert_equal ["paid0: run cap $5.00 reached ($5.50 spent), paid tail off for the rest of this run"], lines
    assert_in_delta 6.5, Tail.spent, 0.001
  end

  def test_a_reply_cost_counts_against_the_cap_from_the_dispatcher
    door = Master::Review::LLMDispatcher.allocate
    door.instance_variable_set(:@bus, nil)
    door.instance_variable_set(:@session, Struct.new(:x) { def record_cost(*, **) = nil }.new)
    door.define_singleton_method(:price_per_token) { |_m, _d| 2.5e-6 }
    door.define_singleton_method(:flat_rate?) { |_m| false }
    door.define_singleton_method(:publish_llm_cost) { |**| nil }

    Master::Trace::Dmesg.stub(:status, ->(*, **) {}) do
      door.send(:record_measured_usage, HAIKU, input: 1_000_000, output: 1_000_000, cached: 0, cache_write: 0, tokens: 2_000_000)
    end

    assert_in_delta 5.0, Tail.spent, 0.001
    assert Tail.capped?
  end

  def test_the_environment_switch_turns_the_tail_off
    ENV["MASTER_PAID_TAIL"] = "0"
    assert_empty Tail.models
    assert_equal [OPUS], Selection.order([OPUS, HAIKU])
  end

  def test_lanes_that_read_images_come_first_when_a_call_carries_one
    Selection.stub(:catalog_modalities, nil) do
      mixed = [GROK, DEEPSEEK, SUPER, GEMMA, OPUS]
      assert_equal [OPUS, GEMMA, GROK, DEEPSEEK, SUPER], Selection.order(mixed, vision: true)
      assert_equal [OPUS, GROK, DEEPSEEK], Selection.order(mixed, vision: false).first(3)
    end
  end

  def test_catalog_modalities_decide_vision_when_the_catalog_has_the_row
    Selection.stub(:catalog_modalities, ->(id) { id == LUNA ? %w[text image] : (id == HAIKU ? ["text"] : nil) }) do
      assert Selection.vision?(LUNA)
      refute Selection.vision?(HAIKU), "a claude name does not outvote the catalog"
    end
  end

  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  class Asked
    attr_reader :models

    def initialize(models) = (@models = models; @asked = [])
    attr_reader :asked

    def candidate_models(_m = nil, task_type: nil) = @models

    def ask_once(_prompt, model: nil, **)
      @asked << model
      "ok"
    end

    def ask(_prompt, **)
      @asked << :routed
      "ok"
    end
  end

  def test_the_council_sends_a_screenshot_to_a_lane_that_reads_it
    Selection.stub(:catalog_modalities, nil) do
      agent = Asked.new([GROK, DEEPSEEK, OPUS, GEMMA])
      personas = Array.new(3) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
      delib = Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)

      personas.each { |p| delib.send(:ask_persona, persona: p, code: "x", context: nil, image: { path: "shot.png" }) }

      # InterModelContract re-asks once when a reply is not its structured
      # shape, and "ok" is not, so each persona may be asked twice: every ask
      # still has to reach the lane that reads images.
      assert_equal [OPUS], agent.asked.uniq, "a lane that cannot see was asked about a screenshot"
      assert_operator agent.asked.size, :>=, personas.size
    end
  end

  def test_an_openrouter_daily_free_limit_is_dead_until_midnight_utc
    now = Time.utc(2026, 10, 11, 21, 24, 31).to_f
    reply = "rate_limit: Rate limit exceeded: free-models-per-day-high-balance. "
    verdict = Master::Io::LaneReply.read(reply, now:)

    assert_equal :spent, verdict.kind
    assert_equal 2 * 3600 + 35 * 60 + 29, verdict.wait
    refute verdict.unknown
  end

  def test_openrouter_header_reset_and_402_are_quota_deaths
    now = Time.utc(2026, 10, 11, 12, 0, 0).to_f
    reset_ms = ((now + 900) * 1000).to_i
    limited = Master::Io::LaneReply.read(%(429 Rate limit exceeded: free-models-per-day {"X-RateLimit-Reset":"#{reset_ms}"}), now:)
    assert_equal 900, limited.wait

    broke = Master::Io::LaneReply.read("402 Insufficient credits. Add more using https://openrouter.ai", now:)
    assert_equal :spent, broke.kind
    Quota.clock = -> { now }
    assert Quota.note(HAIKU, "402 Insufficient credits. Add more using https://openrouter.ai")
    assert Quota.dead?(HAIKU)
  ensure
    Quota.clock = -> { Time.now.to_f }
  end
end
