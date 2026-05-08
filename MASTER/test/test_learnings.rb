# frozen_string_literal: true

require_relative "test_helper"

class TestLearnings < Minitest::Test
  def test_record_and_search_prefers_non_failed_entries
    Dir.mktmpdir do |dir|
      learnings = Master::Learnings.new(root: dir)
      learnings.record(trigger: "rubocop offense", strategy: "run autocorrect", outcome: :fixed)
      learnings.record(trigger: "rubocop offense", strategy: "ignore", outcome: :failed)

      hits = learnings.search("rubocop")

      refute_empty hits
      assert_equal "run autocorrect", hits.first["strategy"]
      refute_includes hits.map { |h| h["outcome"] }, "failed"
    end
  end

  def test_opportunities_identifies_failure_and_corrections
    Dir.mktmpdir do |dir|
      learnings = Master::Learnings.new(root: dir)
      3.times { learnings.record_event(event_type: :tool_failure, dimension: "write_file") }
      3.times { learnings.record_event(event_type: :user_correction, dimension: "style") }
      3.times { learnings.record_event(event_type: :provider_error, dimension: "openrouter") }

      categories = learnings.opportunities.map { |o| o[:category] }

      assert_includes categories, :high_failure
      assert_includes categories, :repeated_correction
      assert_includes categories, :provider_errors
    end
  end
end
