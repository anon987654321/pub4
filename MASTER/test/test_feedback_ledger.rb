# frozen_string_literal: true

require "json"
require "fileutils"
require "sqlite3"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/ground/knowledge_store"
require_relative "../lib/trace/ledger/feedback"

class TestFeedbackLedger < Minitest::Test
  class FakeBus
    attr_reader :subs

    def initialize
      @subs = Hash.new { |h, k| h[k] = [] }
    end

    def subscribe(pattern, &handler)
      @subs[pattern] << handler
    end

    def publish(event, payload = {})
      enriched = payload.merge({ "event" => event, "ts" => 0 })
      @subs.each do |pattern, handlers|
        next unless pattern == event
        handlers.each { |handler| handler.call(enriched) }
      end
    end
  end

  def test_attach_records_tool_success_provider_error_user_correction_and_improvement
    root = Dir.mktmpdir("feedback_ledger")
    bus = FakeBus.new
    learnings = Master::Ground::KnowledgeStore.new(root:)
    rollback_calls = []
    rollback = lambda { |result| rollback_calls << result; true }
    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings:, rollback:).attach
    db = nil

    bus.publish("tool:after", { tool: "write_file", exit_code: 0 })
    bus.publish("llm:call_complete", model: "gpt-4.1", tokens_out: 42)
    bus.publish("llm:provider_outcome", model: "gpt-4.1", status: "provider_error", error: "boom")
    bus.publish("user_correction", action: "/fix")
    bus.publish("fix_loop:soul_proposal", root:, rule: "T205", sample: [{ file: "lib/example.rb" }])
    bus.publish("fix_loop:oscillation", violations: 1)

    db = SQLite3::Database.new(File.join(root, ".master", "knowledge.sqlite3"))
    db.results_as_hash = true
    rows = db.execute("SELECT event_type, dimension, value, metadata FROM feedback_events ORDER BY id")

    types = rows.map { |row| row["event_type"] }
    assert_includes types, "tool_success"
    assert_includes types, "provider_error"
    assert_includes types, "user_correction"
    assert_operator rows.count { |row| row["event_type"] == "tool_success" }, :>=, 2
    assert_equal 1, rollback_calls.size
    assert_equal :policy, rollback_calls.first.category

    log = File.join(root, "runtime", "rsi_improvements.md")
    assert File.exist?(log)
    assert_match(/T205/, File.read(log))
  ensure
    db&.close
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  def test_analyze_self_command_reports_ledger_opportunities
    root = Dir.mktmpdir("analyze_self")
    learnings = Master::Ground::KnowledgeStore.new(root:)
    3.times { learnings.record_event(event_type: "provider_error", dimension: "flaky-model") }

    output = Master::CLI::CommandRegistry.dispatch_analyze_self(learnings:)

    assert_includes output, "provider_errors flaky-model count=3"
  ensure
    learnings&.close
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  def test_provider_errors_are_queryable_separately_with_metadata
    root = Dir.mktmpdir("provider_errors")
    learnings = Master::Ground::KnowledgeStore.new(root:)
    learnings.record_event(
      event_type: "provider_error",
      dimension: "flaky-model",
      value: "rate_limit",
      metadata: { model: "flaky-model", error: "429" },
    )
    learnings.record_event(event_type: "tool_failure", dimension: "shell", value: "1")

    rows = learnings.provider_errors(model: "flaky-model")

    assert_equal 1, rows.size
    assert_equal "flaky-model", rows.first[:model]
    assert_equal "rate_limit", rows.first[:status]
    assert_equal "429", rows.first[:metadata]["error"]
  ensure
    learnings&.close
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end
end
