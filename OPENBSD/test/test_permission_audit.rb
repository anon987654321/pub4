# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/permission_audit"

class TestPermissionAudit < Minitest::Test
  def audit(secrets: [], private_dirs: [], daemon_logs: [])
    Deploy::PermissionAudit.failures(secrets:, private_dirs:, daemon_logs:, daemon_user: "master")
  end

  def test_the_modes_the_scripts_write_pass
    assert_empty audit(
      secrets: [{ path: "/etc/brgen.env", mode: 0o100640 }],
      private_dirs: [{ path: "/home/brgen/app/storage", mode: 0o040750 }],
      daemon_logs: [{ path: "/home/dev/pub4/MASTER/.master/tts-worker-0.log", owner: "master" }]
    )
  end

  def test_a_world_readable_secret_fails
    lines = audit(secrets: [{ path: "/etc/master.env", mode: 0o100644 }])

    assert_equal 1, lines.size
    assert_includes lines.first, "/etc/master.env is 0644"
  end

  # The state the app homes were in until 2026-08-25.
  def test_a_world_readable_storage_directory_fails
    refute_empty audit(private_dirs: [{ path: "/home/amber/app/storage", mode: 0o040755 }])
  end

  # The 2026-09-09 TTS outage: the daemon could not write its own log.
  def test_a_daemon_log_owned_by_root_fails
    lines = audit(daemon_logs: [{ path: ".master/tts-worker-1.log", owner: "root" }])

    assert_includes lines.first, "owned by root"
  end
end
