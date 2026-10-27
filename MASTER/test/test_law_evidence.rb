# frozen_string_literal: true

require_relative "test_helper"

class TestLawEvidence < Minitest::Test
  def test_pledge_unveil_is_applied_at_boot
    boot = File.read(File.join(Master::ROOT, "lib/boot/master_boot.rb"))
    pledge = File.read(File.join(Master::ROOT, "lib/ground/pledge.rb"))
    assert_includes boot, "Ground::Pledge.stage1_boot!"
    assert_includes boot, "Ground::Pledge.stage2_lock!"
    assert_includes pledge, "extern \"int pledge(const char *, const char *)\""
    assert_includes pledge, "extern \"int unveil(const char *, const char *)\""
    assert_includes pledge, "unveil(\"/\", \"\")"
  end

  # Two invocations leave two records: the audit appends rather than rewrites.
  def test_audit_logging_appends_tool_invocations
    Dir.mktmpdir do |root|
      bus = Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root:))
      Master::Trace::Log::Audit.new(root:, event_bus: bus)
      bus.publish("tool:before", tool: "read_file")
      bus.publish("tool:before", tool: "shell")

      records = File.readlines(File.join(root, Master::Trace::Log::Audit::LOG_PATH)).map { |line| JSON.parse(line) }
      assert_equal %w[read_file shell], records.map { |record| record["tool"] }
    end
  end

  def test_secrets_rotation_is_not_a_silent_rotator
    lib = File.join(Master::ROOT, "lib")
    hits = Dir.glob("#{lib}/**/*.rb").count do |path|
      source = File.read(path)
      source.match?(/rotate_(api_key|secret|credential|web_token)/i)
    end
    assert_equal 0, hits, "a credentials rotator appeared — give secrets_rotation a real law_id"
  end
end
