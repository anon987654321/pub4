# frozen_string_literal: true

require_relative "test_helper"

class TestEventBus < Minitest::Test
  def setup
    Fiber[:master_conversation] = nil
    @dir = Dir.mktmpdir
    @bus = Master::Trace::EventBus.new(
      event_log: Master::Trace::Log::Event.new(root: @dir),
    )
  end

  def teardown
    Fiber[:master_conversation] = nil
    FileUtils.rm_rf(@dir)
  end

  def test_nested_publish_is_queued_instead_of_recursing
    seen = []
    @bus.subscribe("outer") do
      seen << :outer
      @bus.publish("inner")
    end
    @bus.subscribe("inner") { seen << :inner }

    @bus.publish("outer")

    assert_equal %i[outer inner], seen
  end

  def test_nested_publish_from_another_fiber_stays_on_the_same_dispatch_queue
    seen = []
    conversation = nil
    @bus.subscribe("outer") do
      seen << :outer
      Fiber.new do
        Fiber[:master_conversation] = "nested-conv"
        @bus.publish("inner")
      ensure
        Fiber[:master_conversation] = nil
      end.resume
    end
    @bus.subscribe("inner") do |event|
      seen << :inner
      conversation = event[:conversation]
    end

    @bus.publish("outer")

    assert_equal %i[outer inner], seen
    assert_equal "nested-conv", conversation
  end

  def test_recursive_event_cascade_is_bounded
    seen = 0
    @bus.subscribe("loop") do
      seen += 1
      @bus.publish("loop") if seen < Master::Trace::EventBus::MAX_DISPATCHED_EVENTS + 10
    end

    @bus.publish("loop")

    assert_equal Master::Trace::EventBus::MAX_DISPATCHED_EVENTS, seen
  end

  def test_handler_failure_never_recurses_through_error_reporting
    @bus.subscribe("outer") { raise "outer failure" }
    @bus.subscribe("error:swallowed") { raise "error reporter failure" }

    @bus.publish("outer")

    assert_equal 1, @bus.instance_variable_get(:@failure_warnings).values.count(true)
  end

  def test_publish_stamps_the_fiber_conversation
    seen = nil
    @bus.subscribe("tool:before") { |ev| seen = ev }
    Fiber[:master_conversation] = "aabbccddeeff00112233445566778899"
    @bus.publish("tool:before", tool: "Write")

    assert_equal "aabbccddeeff00112233445566778899", seen[:conversation]
    assert_equal "Write", seen[:tool]
  end

  def test_publish_omits_conversation_when_the_fiber_is_unset
    seen = nil
    @bus.subscribe("tool:before") { |ev| seen = ev }
    @bus.publish("tool:before", tool: "Write")

    refute seen.key?(:conversation)
  end

  def test_a_handler_can_tell_this_conversation_from_another
    mine = []
    @bus.subscribe("tool:before") do |ev|
      next unless ev[:conversation] == "mine-conv"

      mine << ev[:path]
    end

    Fiber[:master_conversation] = "mine-conv"
    @bus.publish("tool:before", path: "ours.rb")
    Fiber[:master_conversation] = "other-conv"
    @bus.publish("tool:before", path: "theirs.rb")
    Fiber[:master_conversation] = nil
    @bus.publish("tool:before", path: "background.rb")

    assert_equal ["ours.rb"], mine
  end

  # Every persisted line names its session, and a web session by a digest: the
  # conversation id is the cookie that selects a transcript, so it never lands
  # in a log verbatim.
  def test_every_log_line_names_its_session_without_the_bearer
    Master::Trace::Log::Audit.new(root: @dir, event_bus: @bus)
    Fiber[:master_conversation] = "aabbccddeeff00112233445566778899"
    @bus.publish("tool:before", tool: "write_file", path: "web.rb")
    Fiber[:master_conversation] = nil
    @bus.publish("tool:before", tool: "write_file", path: "cli.rb")

    web, cli = log_lines("runtime/events/activity.jsonl")
    audit_web, audit_cli = log_lines(".master/audit.ndjson")
    digest = Digest::SHA256.hexdigest("aabbccddeeff00112233445566778899")[0, Master::Trace::Log::SESSION_DIGEST_CHARS]

    assert_equal [digest, digest], [web["session"], audit_web["session"]]
    assert_equal ["local-#{Process.pid}"] * 2, [cli["session"], audit_cli["session"]]
    refute_includes File.read(File.join(@dir, ".master/audit.ndjson")), "aabbccddeeff00112233445566778899"
    assert Time.iso8601(audit_cli["ts"]), "the audit line keeps its wall clock"
  end

  def test_persisted_tool_arguments_are_hashed_in_activity_and_private_audit
    Master::Trace::Log::Audit.new(root: @dir, event_bus: @bus)
    path = "/private/users/alex/source.rb"
    content = "account secret and private source"
    prompt = "please inspect my private notes"

    @bus.publish(
      "tool:before", tool: "write_file", path:, content:, prompt:,
      op: "write", bytes: content.bytesize
    )

    activity_text = File.read(File.join(@dir, "runtime/events/activity.jsonl"))
    audit_text = File.read(File.join(@dir, ".master/audit.ndjson"))
    [activity_text, audit_text].each do |persisted|
      refute_includes persisted, path
      refute_includes persisted, content
      refute_includes persisted, prompt
      refute_includes persisted, "alex/source.rb"
      assert_includes persisted, Digest::SHA256.hexdigest(path)
      assert_includes persisted, Digest::SHA256.hexdigest(content)
      assert_includes persisted, Digest::SHA256.hexdigest(prompt)
    end

    # The activity log nests an event's fields under payload; the audit line is flat.
    activity = log_lines("runtime/events/activity.jsonl").last.fetch("payload")
    audit = log_lines(".master/audit.ndjson").last
    [activity, audit].each do |record|
      assert_equal "write_file", record["tool"]
      assert_equal "write", record["op"]
      assert_equal content.bytesize, record["bytes"]
      assert_equal Digest::SHA256.hexdigest(path), record["path_digest"]
      assert_equal Digest::SHA256.hexdigest(content), record["content_digest"]
      assert_equal Digest::SHA256.hexdigest(prompt), record["prompt_digest"]
    end
  end

  def test_named_sensitive_fields_are_redacted_outside_tool_events
    command = "env API_TOKEN=secret curl https://private.invalid"
    @bus.publish("zsh:banned_tool_refused", command:, tools: ["sed"])

    activity = File.read(File.join(@dir, "runtime/events/activity.jsonl"))
    refute_includes activity, command
    assert_includes activity, Digest::SHA256.hexdigest(command)
  end

  def test_effect_lifecycle_events_are_written_to_the_operational_evidence_stream
    evidence = Master::Trace::Log::Evidence.new(root: @dir)
    bus = Master::Trace::EventBus.new(
      event_log: Master::Trace::Log::Event.new(root: @dir),
      evidence_log: evidence,
    )

    bus.publish_required("core:effect:before", effect_id: "effect-evidence-1", verb: "write")
    bus.publish_required("core:effect:after", effect_id: "effect-evidence-1", status: "ok")

    activity = log_lines("runtime/events/activity.jsonl")
    operational = log_lines("runtime/events/evidence.jsonl")
    assert_equal %w[core:effect:before core:effect:after], operational.map { |row| row["event"] }
    assert_equal activity.map { |row| row["effect_id"] }, operational.map { |row| row["effect_id"] }
  end

  def test_publish_required_persists_before_dispatching_subscribers
    observed_record = nil
    @bus.subscribe("critical:before") do |_event|
      observed_record = @bus.instance_variable_get(:@event_log).recent(1).last
    end

    @bus.publish_required("critical:before", effect_id: "e-1", verb: "write")

    assert_equal "critical:before", observed_record.fetch("event")
    assert_equal "e-1", observed_record.dig("payload", "effect_id")
    assert_equal "write", observed_record.dig("payload", "verb")
    assert_equal 1, @bus.instance_variable_get(:@event_log).recent(10).count { |record| record["event"] == "critical:before" }
  end

  def test_publish_required_propagates_persistence_failure
    called = false
    broken_log = Object.new
    broken_log.define_singleton_method(:append!) { |*| raise IOError, "disk full" }
    @bus.instance_variable_set(:@event_log, broken_log)
    @bus.subscribe("critical:before") { called = true }

    error = assert_raises(IOError) { @bus.publish_required("critical:before", effect_id: "e-2") }

    assert_match(/required event persistence failed/, error.message)
    refute called, "subscriber dispatch must not precede required persistence"
  end

  private

  def log_lines(relative)
    File.readlines(File.join(@dir, relative)).map { |line| JSON.parse(line) }
  end
end
