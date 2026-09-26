# frozen_string_literal: true

require "json"
require "fileutils"
require "sqlite3"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/ground/knowledge_store"
require_relative "../lib/trace/ledger"

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

  def test_attach_records_tool_success_provider_error_and_improvement
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
    bus.publish("fix_loop:soul_proposal", root:, rule: "T205", sample: [{ file: "lib/example.rb" }])
    bus.publish("ops:commit", root:, message: "fix_loop: llm-fix [pass 1]", head: "abc123", paths: ["lib/example.rb"], findings: [{ rule: "T205" }])
    bus.publish("production:evidence", root:, boundary: "master", signal: "fix.pass", value: 1, source: "test")
    bus.publish("fix_loop:oscillation", violations: 1)

    db = SQLite3::Database.new(File.join(root, ".master", "knowledge.sqlite3"))
    db.results_as_hash = true
    rows = db.execute("SELECT event_type, dimension, value, metadata FROM feedback_events ORDER BY id")

    types = rows.map { |row| row["event_type"] }
    assert_includes types, "tool_success"
    assert_includes types, "provider_error"
    assert_operator rows.count { |row| row["event_type"] == "tool_success" }, :>=, 2
    assert_equal 1, rollback_calls.size
    assert_equal :policy, rollback_calls.first.category

    log = File.join(root, "runtime", "rsi_improvements.md")
    assert File.exist?(log)
    assert_match(/T205/, File.read(log))

    phoenix_log = File.join(root, Master::Phoenix::JOURNAL)
    assert File.exist?(phoenix_log)
    entries = File.readlines(phoenix_log).map { |line| JSON.parse(line) }
    assert_equal %w[change observation], entries.map { |entry| entry.fetch("kind") }
    assert_equal "fix_loop: llm-fix [pass 1]", entries.first.fetch("goal")
    assert_equal 1, entries.first.fetch("evidence").fetch("findings")
  ensure
    db&.close
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  # read_file publishes no tool:after, so the ledger held its failures and none
  # of its successes, and /status reported it failing 100% of calls. Each call
  # below is the dispatcher's bracket, and each tool must count exactly once.
  def test_every_tool_call_counts_once_whether_or_not_the_tool_counts_itself
    root = Dir.mktmpdir("feedback_calls")
    bus = FakeBus.new
    learnings = Master::Ground::KnowledgeStore.new(root:)
    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings:).attach
    call = lambda do |tool, ok:, after: nil, failed: false|
      bus.publish("tool:call", { tool: })
      bus.publish("tool:after", { tool: }.merge(after)) if after
      bus.publish("tool:failed", { tool:, category: :validation }) if failed
      bus.publish("tool:return", { tool:, ok: })
    end

    call.("read_file", ok: true)
    call.("write_file", ok: true, after: { exit_code: 0 })
    call.("zsh", ok: true, after: { exit_code: 1 })
    call.("read_file", ok: false, failed: true)

    db = SQLite3::Database.new(File.join(root, ".master", "knowledge.sqlite3"))
    tally = db.execute("SELECT dimension, event_type FROM feedback_events").tally
    assert_equal({ %w[read_file tool_success] => 1, %w[read_file tool_failure] => 1,
                   %w[write_file tool_success] => 1, %w[zsh tool_failure] => 1 }, tally)
    refute(learnings.opportunities.any? { |row| row[:dimension] == "read_file" })
  ensure
    db&.close
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  # The fix loop and the ledger both wrote rsi_improvements.md for one
  # recurrence, so the log read every improvement twice.
  def test_a_recurring_rule_is_logged_once
    root = Dir.mktmpdir("recurrence_log")
    bus = FakeBus.new
    rsi_log = File.join(root, "runtime", "rsi_improvements.md")
    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.instance_variable_set(:@bus, bus)
    runner.instance_variable_set(:@root, root)
    runner.instance_variable_set(:@rule_recurrence, Hash.new(0))
    recur = -> { 3.times { runner.send(:track_recurrence, [{ rule: "T205", file: "lib/example.rb" }]) } }

    recur.call
    refute File.exist?(rsi_log), "the fix loop wrote the ledger's log itself"

    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings: nil).attach
    recur.call

    assert_equal 1, File.readlines(rsi_log).size, "the ledger did not write to the loop's root"
    assert_equal 2, File.readlines(File.join(root, "runtime", "improvements.md")).size
  ensure
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  # Tools publish tool:after only when they succeed, so a failing tool left no
  # row at all and every tool the ledger knew read as healthy.
  def test_a_failing_model_called_tool_is_a_failure_and_status_reports_the_rate
    root = Dir.mktmpdir("tool_failure")
    bus = FakeBus.new
    learnings = Master::Ground::KnowledgeStore.new(root:)
    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings:).attach
    broken = Class.new do
      const_set(:NAME, "web_fetch")
      def call(**) = Master::Result.err("timeout", category: :infrastructure)
    end
    wrapper = Master::Io::LLM::WebFetch.new(broken.new, bus:)

    # Three different pages: the same call three times running is refused as a
    # loop rather than run, which is what test_opencrabs_guards holds.
    %w[one two three].each { |page| assert_match(/\AError: timeout/, wrapper.execute(url: "https://example.org/#{page}")) }
    3.times { bus.publish("tool:after", tool: "dynamic_http", status: 503) }
    3.times { bus.publish("tool:after", tool: "read_file") }

    failures = learnings.opportunities.select { |row| row[:category] == :high_failure }
    assert_equal %w[dynamic_http web_fetch], failures.map { |row| row[:dimension] }.sort
    status = Master::CLI::CommandRegistry.render_status_lines(
      { ahead_behind: [0, 0], svc: {}, failures: [], rsi: learnings.opportunities },
    )
    assert_includes status, "learn0: web_fetch failed 100% of 3 calls"
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
