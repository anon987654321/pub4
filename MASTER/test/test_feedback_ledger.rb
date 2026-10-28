# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "fileutils"
require "digest"
require "sqlite3"
require "tmpdir"
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

  # Phoenix journals a commit under the boundary its paths fall in, found from
  # the checkout's .git, so the fixture is a checkout with a MASTER tree.
  def with_env(key, value)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old
  end

  def test_attach_records_tool_success_provider_error_and_improvement
    checkout = Dir.mktmpdir("feedback_ledger")
    FileUtils.mkdir_p(File.join(checkout, ".git"))
    root = File.join(checkout, "MASTER")
    FileUtils.mkdir_p(root)
    bus = FakeBus.new
    learnings = Master::Ground::KnowledgeStore.new(root:)
    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings:).attach
    db = nil

    bus.publish("tool:after", { tool: "write_file", exit_code: 0 })
    bus.publish("llm:call_complete", model: "gpt-4.1", tokens_out: 42)
    bus.publish("llm:provider_outcome", model: "gpt-4.1", status: "provider_error", error: "boom")
    bus.publish("fix_loop:soul_proposal", root:, law: "T205", sample: [{ file: "lib/example.rb" }])
    bus.publish("ops:commit", root:, message: "fix_loop: llm-fix [pass 1]", head: "abc123",
                              paths: ["lib/example.rb"], findings: [{ law: "T205" }])
    bus.publish("fix_loop:oscillation", violations: 1)

    db = SQLite3::Database.new(File.join(root, ".master", "knowledge.sqlite3"))
    db.results_as_hash = true
    rows = db.execute("SELECT event_type, dimension, value, metadata FROM feedback_events ORDER BY id")

    types = rows.map { |row| row["event_type"] }
    assert_includes types, "tool_success"
    assert_includes types, "provider_error"
    assert_operator rows.count { |row| row["event_type"] == "tool_success" }, :>=, 2
    assert_empty Dir.glob(File.join(root, "runtime", "**", "*"))
    assert_equal 1, rows.count { |row| row["event_type"] == "fix_improvement" }
    assert_equal "T205", rows.find { |row| row["event_type"] == "fix_improvement" }["dimension"]

    phoenix_log = File.join(root, Master::Phoenix::JOURNAL)
    assert File.exist?(phoenix_log)
    entries = File.readlines(phoenix_log).map { |line| JSON.parse(line) }
    assert_equal %w[change], entries.map { |entry| entry.fetch("kind") }
    assert_equal "fix_loop: llm-fix [pass 1]", entries.first.fetch("goal")
    assert_equal 1, entries.first.fetch("evidence").fetch("findings")
  ensure
    db&.close
    FileUtils.remove_entry(checkout) if checkout && Dir.exist?(checkout)
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

  # The state PassRunner#initialize gives track_recurrence, and the method opened up.
  class RecurrenceRunner < Master::Fix::FixLoop::PassRunner
    def initialize(bus:, root:)
      @bus = bus
      @root = root
      @law_recurrence = Hash.new(0)
    end

    public :track_recurrence
  end

  # One recurrence event produces one persisted knowledge event. No markdown
  # sidecar or retired runtime directory is created.
  def test_a_recurring_rule_is_logged_once
    root = Dir.mktmpdir("recurrence_log")
    bus = FakeBus.new
    learnings = Master::Ground::KnowledgeStore.new(root:)
    runner = RecurrenceRunner.new(bus:, root:)
    recur = -> { 3.times { runner.track_recurrence([{ law: "T205", file: "lib/example.rb" }]) } }

    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings:).attach
    recur.call
    recur.call

    db = SQLite3::Database.new(File.join(root, ".master", "knowledge.sqlite3"))
    db.results_as_hash = true
    rows = db.execute("SELECT dimension FROM feedback_events WHERE event_type = 'fix_improvement'")
    assert_equal %w[T205 T205], rows.map { |row| row["dimension"] }
    refute Dir.exist?(File.join(root, "runtime")), "retired runtime namespace was created"
  ensure
    db&.close
    learnings&.close
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
    # 70ab4875c keeps opportunities out of the quiet status; verbose shows them.
    status = with_env("MASTER_CLI_VERBOSE", "1") do
      Master::CLI::CommandRegistry.render_status_lines(
        { ahead_behind: [0, 0], svc: {}, failures: [], rsi: learnings.opportunities },
      )
    end
    assert_includes status, "opportunity: web fetch failed 100% of 3 calls"
  ensure
    learnings&.close
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  def test_feedback_metadata_redacts_tool_inputs_and_outputs
    root = Dir.mktmpdir("feedback_redaction")
    bus = FakeBus.new
    learnings = Master::Ground::KnowledgeStore.new(root:)
    Master::Trace::Ledger::Feedback.new(event_bus: bus, learnings:).attach
    private_url = "https://private.example/path?access_token=top-secret"
    private_output = "account=private-customer; returned document contents"
    private_error = "provider returned private response body"
    bus.publish(
      "tool:after",
      tool: "web_fetch", status: 200, url: private_url,
      output: private_output, bytes: private_output.bytesize,
      newly_added_field: private_error
    )
    bus.publish("tool:failed", tool: "web_fetch", category: :infrastructure, error: private_error)

    db = SQLite3::Database.new(File.join(root, ".master", "knowledge.sqlite3"))
    db.results_as_hash = true
    rows = db.execute(
      "SELECT event_type, metadata FROM feedback_events WHERE dimension = ? ORDER BY id",
      ["web_fetch"],
    )
    success = JSON.parse(rows.find { |row| row["event_type"] == "tool_success" }["metadata"])
    failure = JSON.parse(rows.find { |row| row["event_type"] == "tool_failure" }["metadata"])
    persisted = rows.map { |row| row["metadata"] }.join("\\n")

    assert_equal Digest::SHA256.hexdigest(private_url), success.fetch("url_digest")
    assert_equal private_url.bytesize, success.fetch("url_bytes")
    assert_equal Digest::SHA256.hexdigest(private_output), success.fetch("output_digest")
    assert_equal private_output.bytesize, success.fetch("output_bytes")
    assert_equal 1, success.fetch("extra_fields_count")
    assert_equal Digest::SHA256.hexdigest(private_error), failure.fetch("error_digest")
    assert_equal private_error.bytesize, failure.fetch("error_bytes")
    [private_url, private_output, private_error, "top-secret"].each do |secret|
      refute_includes persisted, secret
    end
  ensure
    db&.close
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
