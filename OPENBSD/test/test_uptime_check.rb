# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

# usr/local/bin/uptime-check.sh: a down endpoint is one syslog line at first and a
# durable pub4-alert record once it persists. Fake curl, ruby34 and logger go first
# on PATH; the alert is a recording stub, so nothing leaves the scratch directory.
class TestUptimeCheck < Minitest::Test
  SCRIPT = File.expand_path("../usr/local/bin/uptime-check.sh", __dir__)

  def setup
    @dir = Dir.mktmpdir("uptime-test")
    FileUtils.mkdir_p(File.join(@dir, "fake"))
    write_fake("ruby34", "printf 'brgen,https://brgen.no/up\\namber,https://amberapp.art/up\\n'")
    write_fake("logger", "echo \"$@\" >> #{@dir}/syslog")
    write_fake("curl", "case \"$*\" in *amberapp.art*) echo 'curl: (7)' >&2; exit 7 ;; *) printf 200 ;; esac")
    File.write(File.join(@dir, "alert"), "#!/bin/sh\necho \"$@\" >> #{@dir}/alerts\n")
    File.chmod(0o755, File.join(@dir, "alert"))
  end

  def teardown = FileUtils.rm_rf(@dir)

  def write_fake(name, body)
    path = File.join(@dir, "fake", name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def tick
    env = { "UPTIME_PATH_PREFIX" => File.join(@dir, "fake"), "UPTIME_FAIL_STATE" => File.join(@dir, "count"),
            "PUB4_ALERT" => File.join(@dir, "alert"), "PUB4_ROOT" => @dir }
    _, err, status = Open3.capture3(env, "ksh", SCRIPT)
    [err, status.exitstatus]
  end

  def alerts = File.exist?(File.join(@dir, "alerts")) ? File.read(File.join(@dir, "alerts")) : ""

  def test_a_down_endpoint_alerts_only_when_it_persists
    2.times do
      err, status = tick
      assert_equal 1, status
      assert_includes err, "DOWN https://amberapp.art/up (000)"
    end
    assert_equal "", alerts, "two failed ticks can be a deploy restarting an app"

    tick
    assert_includes alerts, "raise uptime-down down for 3 consecutive checks: https://amberapp.art/up"
    assert_includes File.read(File.join(@dir, "syslog")), "uptime-check"
  end

  def test_a_passing_tick_resets_the_count
    2.times { tick }
    write_fake("curl", "printf 200")
    _, status = tick
    assert_equal 0, status
    assert_equal "0", File.read(File.join(@dir, "count")).strip

    write_fake("curl", "echo x >&2; exit 7")
    2.times { tick }
    assert_equal "", alerts
  end
end
