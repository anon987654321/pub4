# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

# vps-state is what an operator reads first, so a failed stamp and a recorded
# alert must both show in it. DEPLOY_ASSUME_VPS=1 runs the box path on any host;
# the service reads degrade to "unknown" without doas.
class TestVpsState < Minitest::Test
  SCRIPT = File.expand_path("../bin/vps-state", __dir__)

  def state(dir)
    env = { "DEPLOY_ASSUME_VPS" => "1", "PUB4_STAMP_DIR" => dir, "PUB4_ALERT_LOG" => File.join(dir, "alerts.log") }
    out, err, status = Open3.capture3(env, RbConfig.ruby, SCRIPT)
    assert status.success?, err
    out
  end

  def test_a_failed_last_deploy_shows_its_status
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "last_deploy_amber.json"), '{"app":"amber","sha":"abc123","at":"2026-10-10T09:29:57Z","status":"failed"}')

      assert_match(/deploy0 at amber: sha=abc123 at=\S+ status=failed/, state(dir))
    end
  end

  def test_production_status_reader_uses_fixed_broker_verb
    source = File.read(SCRIPT)

    assert_includes source, 'Open3.capture2e("doas", "-n", broker, "deploy-status-read", app)'
    assert_includes source, 'broker = "/usr/local/sbin/pub4-admin"'
    assert_includes source, 'STAMP_DIR == "/var/db/pub4"'
  end

  def test_corrupt_in_progress_deploy_status_is_visible
    Dir.mktmpdir do |dir|
      status_dir = File.join(dir, "deploy_status")
      FileUtils.mkdir_p(status_dir)
      File.write(File.join(status_dir, "amber.json"), "{broken json")

      output = state(dir)

      assert_match(/deploy0 at amber: state=corrupt step=status metadata corrupt/, output)
      assert_match(/JSON::ParserError/, output)
    end
  end

  def test_recorded_alerts_show_newest_first_and_a_quiet_box_shows_none
    Dir.mktmpdir do |dir|
      refute_includes state(dir), "alert0"

      File.write(File.join(dir, "alerts.log"), "2026-10-12T01:00:00Z swap first\n2026-10-12T02:00:00Z disk-home second\n")
      lines = state(dir).lines.grep(/alert0/)

      assert_equal 2, lines.size
      assert_includes lines.first, "disk-home second"
    end
  end
end
