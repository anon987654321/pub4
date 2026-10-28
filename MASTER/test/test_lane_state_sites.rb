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
