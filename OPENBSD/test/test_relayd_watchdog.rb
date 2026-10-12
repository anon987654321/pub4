# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

# relayd-watchdog heals by restarting; the third restart inside the window must
# also leave a durable alert, or the heal hides a recurring fault.
SCRATCH = Dir.mktmpdir("watchdog-test")
ENV["PUB4_WATCHDOG_STATE"] = File.join(SCRATCH, "restarts")
ENV["PUB4_ALERT"] = "pub4-alert-under-test"
Minitest.after_run { FileUtils.rm_rf(SCRATCH) }
require "fileutils"
load File.expand_path("../usr/local/bin/relayd-watchdog", __dir__)

class TestRelaydWatchdog < Minitest::Test
  COMMANDS = []

  def setup
    COMMANDS.clear
    FileUtils.rm_f(RESTART_STATE)
    top.define_singleton_method(:run) { |*cmd| COMMANDS << cmd; [true, ""] }
    top.define_singleton_method(:log) { |_message| nil }
  end

  # The watchdog's methods are private on main; Minitest::Test has its own `run`.
  def top = TOPLEVEL_BINDING.receiver

  def record_restart(*args, **kw) = top.send(:record_restart, *args, **kw)
  def recent_restarts(**kw) = top.send(:recent_restarts, **kw)
  def restart_relayd(reason) = top.send(:restart_relayd, reason)

  def alerts = COMMANDS.select { |c| c.first == "pub4-alert-under-test" }

  def test_two_restarts_in_the_window_are_healing_and_raise_nothing
    2.times { |i| record_restart("relayd check failed", now: 1_000 + i) }

    assert_empty alerts
  end

  def test_the_third_restart_in_the_window_raises_one_alert_naming_what_to_read
    3.times { |i| record_restart("relayd check failed", now: 1_000 + i * 60) }

    assert_equal 1, alerts.size
    assert_equal %w[pub4-alert-under-test raise relayd-restarts], alerts.first.first(3)
    assert_includes alerts.first.last, "restarted 3 times in 60 minutes"
    assert_includes alerts.first.last, "/var/log/daemon"
  end

  def test_restarts_outside_the_window_do_not_count
    record_restart("a", now: 1_000)
    record_restart("b", now: 1_000 + 100)
    record_restart("c", now: 1_000 + RESTART_WINDOW + 500)

    assert_empty alerts
    assert_equal 1, recent_restarts(now: 1_000 + RESTART_WINDOW + 500).size
  end

  def test_an_unwritable_counter_is_reported_and_does_not_stop_the_restart
    Object.send(:remove_const, :RESTART_STATE)
    Object.const_set(:RESTART_STATE, File.join(SCRATCH, "no", "such", "dir", "restarts"))

    assert_equal 0, record_restart("x", now: 5)
  ensure
    Object.send(:remove_const, :RESTART_STATE)
    Object.const_set(:RESTART_STATE, File.join(SCRATCH, "restarts"))
  end

  def test_restart_relayd_restarts_first_and_then_counts
    restart_relayd("relayd check failed")

    assert_equal ["/usr/sbin/rcctl", "restart", "relayd"], COMMANDS.first
    assert_equal 1, recent_restarts.size
  end
end
