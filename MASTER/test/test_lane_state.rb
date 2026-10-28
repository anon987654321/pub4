# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/lane_state"

class TestLaneState < Minitest::Test
  State = Master::Io::LaneState

  def setup = Master::Io::ModelSkipCache.clear!

  def teardown = Master::Io::ModelSkipCache.clear!

  def test_a_model_no_store_refuses_is_usable
    verdict = State.verdict("claude-cli:claude-opus-5-5")

    assert verdict.usable?
    assert_nil verdict.reason
  end

  def test_a_parked_model_names_the_store_and_its_reason
    Master::Io::ModelSkipCache.skip!("x-ai/grok-4.3", reason: "HTTP 429, retry after 90s", category: :rate_limit)
    verdict = State.verdict("x-ai/grok-4.3")

    refute verdict.usable?
    assert_equal :parked, verdict.source
    assert_match(/retry after 90s/, verdict.reason)
  end

  def test_a_lane_dead_by_hand_is_refused_before_anything_else
    Master::Io::LaneQuota.stub(:manual_dead, ["gemini"]) do
      verdict = State.verdict("gemini-2.5-flash")

      assert_equal :dead, verdict.source
    end
  end

  def test_filter_keeps_order_and_drops_refused_models
    Master::Io::ModelSkipCache.skip!("b", reason: "down", category: :provider_error)

    assert_equal %w[a c], State.filter(%w[a b c])
  end
# The services' vocabulary: ready only after a call succeeded.
def test_health_reads_in_the_one_vocabulary
  assert_equal "configured: not asked yet", State.health("claude-cli:claude-opus-5-5")
  assert_equal "ready", State.health("claude-cli:claude-opus-5-5", succeeded: true)

  Master::Io::ModelSkipCache.skip!("x-ai/grok-4.3", reason: "HTTP 429", category: :rate_limit)
  assert_match(/\Adegraded: parked/, State.health("x-ai/grok-4.3", succeeded: true))
end

  def test_a_narrower_question_names_only_its_own_stores
    Master::Io::ModelSkipCache.skip!("x-ai/grok-4.3", reason: "HTTP 429", category: :rate_limit)

    assert State.usable?("x-ai/grok-4.3", sources: State::DOWN)
    assert_equal :parked, State.verdict("x-ai/grok-4.3").source
  end

  STORE_READS = {
    "LaneHealth" => %w[dead?],
    "LaneSilence" => %w[refuses? silent? refusal],
    "LaneQuota" => %w[dead? until_for report_for report reasons manual_dead dead_lanes run_drops lane_of
                      revival_in due_probes raw table],
    "ModelSkipCache" => %w[skipped? filter skip_reason skipped_until_ms],
    "QuotaCheck" => %w[blocked?],
    "ModelQuota" => %w[over_quota?],
  }.freeze

  STORE_READ_PATTERNS = STORE_READS.map do |store, names|
    /\b#{store}\.(?:#{names.map { |name| Regexp.escape(name) }.join("|")})(?![\w?!])/
  end

  LIB = File.expand_path("../lib", __dir__)

  OWNERS = (Dir[File.join(LIB, "io", "lane_*.rb")] +
            %w[model_skip_cache model_quota quota_check].map { |name| File.join(LIB, "io", "#{name}.rb") }).freeze

  # A store read outside the lane files is a second answer to "may I call this
  # model". The stores keep their writers (note, skip!, silence, trip!, record)
  # and their own metrics; these are the reads LaneState owns.
  def test_no_store_refusal_is_read_outside_the_lane_files
    found = (Dir[File.join(LIB, "**", "*.rb")] - OWNERS).flat_map { |path| store_reads_in(path) }

    assert_empty found, "ask Io::LaneState (with sources: when a site must keep something) instead"
  end

  def store_reads_in(path)
    File.readlines(path).each_with_index.filter_map do |line, index|
      next if line.lstrip.start_with?("#") || STORE_READ_PATTERNS.none? { |read| read.match?(line) }

      "#{path.delete_prefix("#{LIB}/")}:#{index + 1}: #{line.strip}"
    end
  end
end
