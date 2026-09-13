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

  private

  def log_lines(relative)
    File.readlines(File.join(@dir, relative)).map { |line| JSON.parse(line) }
  end
end
