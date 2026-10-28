# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"
require_relative "../lib/operator/fix_status"
require "set"
require "tmpdir"

# Every site that asks "may I call this model" asks Io::LaneState, some with a
# narrower `sources:` they say the reason for. One test per site: which models
# it refuses now, and in what words.
class TestLaneStateSites < Minitest::Test
  State = Master::Io::LaneState
  Quota = Master::Io::LaneQuota
  Silence = Master::Io::LaneSilence
  Skip = Master::Io::ModelSkipCache
  Check = Master::Io::QuotaCheck

  PARKED = "x-ai/grok-4.3"
  SILENT = "deepseek-chat"
  LIVE = "mistral-large-latest"
  HAND = "gemini-2.5-flash"

  def setup
    @dir = Dir.mktmpdir
    Quota.path = File.join(@dir, "lane_quota.yml")
    Skip.skip!(PARKED, reason: "HTTP 429", category: :rate_limit)
    Silence.silence(Silence.lane_of(SILENT), reason: "no answer in 90s")
  end

  def teardown
    Skip.clear!
    Check.reset!
    Quota.clear_run_drops!
    [PARKED, SILENT, LIVE, HAND].each { |model| Silence.record(true, Silence.lane_of(model)) }
    Quota.path = nil
    FileUtils.remove_entry(@dir)
  end

  def test_pool_refuses_only_a_dead_lane
    restore = Master::TestSupport::RoutingIsolation.install
    config = Master::TestSupport::FakeConfig.new(model: LIVE)
    router = Master::CLI::Routing::ModelRouter.new(config:, root: Master::ROOT)
    Quota.drop_for_run!("grok-cli", "probe timed out")

    assert_equal "grok-cli: dropped for this run (probe timed out)", router.unreachable_reason("grok-cli:auto")
    Quota.stub(:manual_dead, ["gemini"]) do
      assert_equal "gemini: dead by hand (data/lanes.yml dead:)", router.unreachable_reason(HAND)
    end
    refute_match(/parked|answer in/, router.unreachable_reason(PARKED).to_s, "a parked model stays a candidate")
    refute_match(/parked|answer in/, router.unreachable_reason(SILENT).to_s, "a silent lane keeps its probe")
  ensure
    restore&.call
  end

  def test_the_route_drops_a_parked_model_and_puts_a_silent_lane_behind_a_usable_one
    restore = Master::TestSupport::RoutingIsolation.install
    config = Master::TestSupport::FakeConfig.new(model: LIVE)
    router = Master::CLI::Routing::ModelRouter.new(config:, root: Master::ROOT)
    router.define_singleton_method(:chain_for) { |_task| [PARKED, SILENT, LIVE] }
    router.define_singleton_method(:reachable?) { |_id| true }

    chain = router.fallback_chain(task_type: :exploration)

    assert_includes chain, LIVE
    refute_includes chain, PARKED
    refute_includes chain, SILENT
  ensure
    restore&.call
  end

  def test_the_fallback_walk_skips_every_refused_model_and_names_its_store
    agent = Master::Review::Agent.allocate
    warnings = []
    skip = ->(model) { agent.send(:skip_fallback_attempt?, model, timed_out_models: Set.new, stage_warnings: warnings) }

    assert skip.call(PARKED)
    assert skip.call(SILENT)
    Quota.stub(:manual_dead, ["gemini"]) { assert skip.call(HAND) }
    refute skip.call(LIVE)
    assert_equal ["skipped #{PARKED} (parked: parked: HTTP 429)", "skipped #{SILENT} (silent: ",
                  "skipped #{HAND} (dead: gemini: dead by hand (data/lanes.yml dead:))"],
                 [warnings[0], warnings[1][0, "skipped #{SILENT} (silent: ".size], warnings[2]]
  end

  # The agent's offline line and /fix status's online line both count down lanes only.
  def test_offline_is_said_for_down_lanes_but_not_for_a_parked_model
    agent = Master::Review::Agent.allocate
    last = Master::Result.err("HTTP 429", category: :rate_limit)

    agent.define_singleton_method(:single_call_fallback_models) { [] }
    assert_same last, agent.send(:offline_when_exhausted, last, PARKED), "a parked model says its own failure"

    result = agent.send(:offline_when_exhausted, last, SILENT)
    assert_equal :offline, result.category
    assert_match(/\Aoffline: no lane answers; deepseek: silent/, result.message)

    Master::Io::LaneSelection.stub(:catalogue, [SILENT, PARKED]) do
      assert_equal "online: yes via #{PARKED}", ::Operator::FixStatus.new(root: @dir).send(:online_line)
    end
  end

  def test_a_persona_on_a_refused_lane_is_not_asked
    council = Master::Review::Council::Deliberation.allocate
    council.instance_variable_set(:@persona_failures_lock, Mutex.new)
    council.instance_variable_set(:@persona_failures, [])
    persona = Struct.new(:name).new("Skeptic")
    lane = nil
    council.define_singleton_method(:lane_for) { |_persona, image: nil| lane }

    lane = PARKED
    assert_nil council.send(:ask_persona, persona:, code: "x", context: nil)
    lane = SILENT
    assert_nil council.send(:ask_persona, persona:, code: "x", context: nil)
    lane = nil
    Check.trip!(source: "test", message: "Insufficient credits")
    assert_nil council.send(:ask_persona, persona:, code: "x", context: nil)

    tally = council.instance_variable_get(:@persona_failures)
    assert_equal %w[skipped_parked skipped_silent skipped_spend_limit], tally
  end

  def test_the_model_list_names_the_store_that_refuses
    router = Object.new
    router.define_singleton_method(:hosted_endpoint_for) { |_id| nil }
    pool = Master::CLI::Routing::ComputePool.new(router:, root: @dir)

    assert_equal :parked, pool.send(:quota_state, PARKED)
    assert_equal :silent, pool.send(:quota_state, SILENT)
    Quota.stub(:manual_dead, ["gemini"]) { assert_equal :dead, pool.send(:quota_state, HAND) }
    refute_includes %i[parked silent dead exhausted], pool.send(:quota_state, LIVE)
  end
end
