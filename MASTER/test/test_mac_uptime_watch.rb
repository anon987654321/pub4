# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"

class TestMacUptimeWatch < Minitest::Test
  SCRIPT = File.expand_path("../bin/mac-uptime-watch.sh", __dir__)

  def setup
    @home = Dir.mktmpdir("pub4-uptime-home-")
    @bin = File.join(@home, "bin")
    FileUtils.mkdir_p(@bin)
    @notifications = File.join(@home, "notifications.log")
    write_command("curl", <<~RUBY)
      #!/usr/bin/env ruby
      print ENV.fetch("PUB4_TEST_HTTP_CODE", "200")
    RUBY
    write_command("osascript", <<~RUBY)
      #!/usr/bin/env ruby
      File.open(ENV.fetch("PUB4_TEST_NOTIFY_LOG"), "a") { |file| file.puts(ARGV.join(" ")) }
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && File.exist?(@home)
  end

  def test_stale_lock_is_recovered_and_alerts_only_on_threshold_crossing
    lock = File.join(@home, ".pub4", "uptime_watch.lock")
    FileUtils.mkdir_p(lock)
    File.write(File.join(lock, "pid"), "99999999\n")
    old = Time.now - 120
    File.utime(old, old, lock)

    assert_equal 0, tick("503"), "first failed tick stays below threshold"
    refute File.exist?(lock), "the stale lock must be reclaimed"

    assert_equal 1, tick("503"), "second failure crosses the alert threshold"
    assert_equal 1, File.readlines(@notifications).size

    assert_equal 1, tick("503"), "continued outage remains non-zero for cron"
    assert_equal 1, File.readlines(@notifications).size, "do not repeat the same outage alert every tick"

    assert_equal 0, tick("200"), "healthy endpoint clears the failure streak"
    assert_equal 2, File.readlines(@notifications).size
    assert_match(/DOWN one\.test/, File.read(File.join(@home, ".pub4", "uptime_watch.log")))
    assert_match(/RECOVERED one\.test/, File.read(File.join(@home, ".pub4", "uptime_watch.log")))
  end

  def test_watch_has_no_external_text_filter_dependencies
    source = File.read(SCRIPT)
    refute_match(/\b(?:awk|tail)\b/, source)
  end

  private

  def write_command(name, source)
    path = File.join(@bin, name)
    File.write(path, source)
    File.chmod(0o755, path)
  end

  def tick(code)
    path = [@bin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)
    env = {
      "HOME" => @home,
      "PATH" => path,
      "PUB4_UPTIME_HOSTS" => "one.test",
      "PUB4_UPTIME_WAIVED" => "",
      "PUB4_UPTIME_FAILS" => "2",
      "PUB4_TEST_HTTP_CODE" => code,
      "PUB4_TEST_NOTIFY_LOG" => @notifications,
    }
    system(env, "/bin/zsh", SCRIPT, out: File::NULL, err: File::NULL)
    $?.exitstatus
  end
end
