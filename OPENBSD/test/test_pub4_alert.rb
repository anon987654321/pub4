# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

# usr/local/bin/pub4-alert: the durable alert that a healed or noted symptom lands
# in. Every external read (df, swapctl, rcctl) is a fake first on PATH, and the
# log, state and marker are scratch paths, so nothing here touches the machine.
class TestPub4Alert < Minitest::Test
  SCRIPT = File.expand_path("../usr/local/bin/pub4-alert", __dir__)

  def fake(dir, name, body)
    FileUtils.mkdir_p(File.join(dir, "fake"))
    path = File.join(dir, "fake", name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def env(dir, extra = {})
    {
      "PUB4_ALERT_PATH_PREFIX" => File.join(dir, "fake"),
      "PUB4_ALERT_LOG" => File.join(dir, "alerts.log"),
      "PUB4_ALERT_STATE" => File.join(dir, "state"),
      "PUB4_ALERT_LOGGER" => "true",
      "PUB4_DR_MARKER" => File.join(dir, "marker"),
    }.merge(extra)
  end

  def run_alert(dir, *args, **extra)
    out, err, status = Open3.capture3(env(dir, extra), "ksh", SCRIPT, *args)
    [out + err, status.exitstatus]
  end

  def log(dir)
    File.exist?(File.join(dir, "alerts.log")) ? File.read(File.join(dir, "alerts.log")) : ""
  end

  def quiet_box(dir)
    fake(dir, "df", %(echo "Filesystem 512-blocks Used Available Capacity Mounted on"; echo "/dev/sd0k 100 76 24 76% /home"))
    fake(dir, "swapctl", %(echo "total: 2588672 512-blocks allocated, 1000000 used, 1588672 available"))
    fake(dir, "rcctl", "exit 0")
    File.write(File.join(dir, "marker"), Time.now.to_i.to_s)
  end

  def test_a_healthy_box_records_nothing
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      _, status = run_alert(dir, "watch")

      assert_equal 0, status
      assert_equal "", log(dir)
    end
  end

  def test_raise_records_once_per_key_in_the_quiet_window_and_again_after_it
    Dir.mktmpdir do |dir|
      run_alert(dir, "raise", "relayd-restarts", "relayd restarted 3 times")
      run_alert(dir, "raise", "relayd-restarts", "relayd restarted 4 times")
      run_alert(dir, "raise", "other", "a different fault")

      assert_equal 2, log(dir).lines.size, log(dir)
      assert_match(/\A\d{4}-\d\d-\d\dT[\d:]+Z relayd-restarts relayd restarted 3 times$/, log(dir).lines.first)

      run_alert(dir, "raise", "relayd-restarts", "still failing", "PUB4_ALERT_QUIET" => "0")
      assert_includes log(dir), "relayd-restarts still failing"
    end
  end

  def test_raise_refuses_a_key_that_could_escape_the_state_directory
    Dir.mktmpdir do |dir|
      _, status = run_alert(dir, "raise", "../x", "nope")

      assert_equal 2, status
      assert_equal "", log(dir)
    end
  end

  def test_watch_names_a_full_filesystem_with_the_command_to_find_the_growth
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "df", %(echo "Filesystem 512-blocks Used Available Capacity Mounted on"; echo "/dev/sd0k 100 95 5 95% /home"; echo "/dev/sd0a 100 20 80 20% /"))
      run_alert(dir, "watch")

      assert_includes log(dir), "disk-home /home is 95% full"
      assert_includes log(dir), "doas du -xk /home"
      refute_includes log(dir), "disk-root"
    end
  end

  def test_watch_names_swap_pressure
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "swapctl", %(echo "total: 2588672 512-blocks allocated, 2500000 used, 88672 available"))
      run_alert(dir, "watch")

      assert_includes log(dir), "swap swap is 96% used"
    end
  end

  def test_watch_ignores_the_designed_failure_and_names_any_other
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "rcctl", %(printf 'brgen_jobs\\nsmtpd\\n'))
      run_alert(dir, "watch")

      refute_includes log(dir), "failed-brgen_jobs"
      assert_includes log(dir), "failed-smtpd smtpd is in rcctl failed"
    end
  end

  def test_watch_flags_a_missing_and_a_stale_backup_report
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      File.delete(File.join(dir, "marker"))
      run_alert(dir, "watch")
      assert_includes log(dir), "backup-unreported"

      File.write(File.join(dir, "marker"), (Time.now.to_i - 4 * 86_400).to_s)
      run_alert(dir, "watch")
      assert_match(/backup-stale the newest dr-pull reported 96 hours ago/, log(dir))
    end
  end

  def test_show_prints_the_last_alerts
    Dir.mktmpdir do |dir|
      3.times { |i| run_alert(dir, "raise", "k#{i}", "message #{i}") }
      out, status = run_alert(dir, "show", "2")

      assert_equal 0, status
      assert_equal 2, out.lines.size
      assert_includes out, "k2 message 2"
      refute_includes out, "k0"
    end
  end
end
