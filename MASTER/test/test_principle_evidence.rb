# frozen_string_literal: true

require_relative "test_helper"

# pledge_unveil, audit_logging and secrets_rotation sat in principle_map.yml
# with empty rule_ids. Linking them to an unrelated registered rule would
# close the map gap without an evidence source. These tests pin the sources
# that exist, and refuse to invent a rotator that does not.
class TestPrincipleEvidence < Minitest::Test
  def test_pledge_unveil_is_applied_at_boot
    boot = File.read(File.join(Master::ROOT, "lib/boot/master_boot.rb"))
    pledge = File.read(File.join(Master::ROOT, "lib/ground/pledge.rb"))
    assert_includes boot, "Ground::Pledge.stage1_boot!"
    assert_includes boot, "Ground::Pledge.stage2_lock!"
    assert_includes pledge, "extern \"int pledge(const char *, const char *)\""
    assert_includes pledge, "extern \"int unveil(const char *, const char *)\""
    assert_includes pledge, "unveil(\"/\", \"\")"
  end

  def test_audit_logging_appends_tool_invocations
    audit = File.read(File.join(Master::ROOT, "lib/trace/log/audit.rb"))
    assert_includes audit, "event_bus.subscribe(\"tool:before\")"
    assert_includes audit, "File.open(@path, \"a\")"
    refute_includes audit.gsub(/^\s*#.*$/, ""), "File.write(@path"
  end

  def test_secrets_rotation_is_not_a_silent_rotator
    # Credentials live in /etc/*.env on vm23 and rotate by operator. A
    # principle_map row that pointed at SECRET_PROXIMITY would report rotation
    # coverage for a proximity rule. Absence of a rotator is the finding.
    lib = File.join(Master::ROOT, "lib")
    hits = Dir.glob("#{lib}/**/*.rb").count do |path|
      source = File.read(path)
      source.match?(/rotate_(api_key|secret|credential|web_token)/i)
    end
    assert_equal 0, hits, "a credentials rotator appeared — give secrets_rotation a real rule_id"
  end
end
