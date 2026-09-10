# frozen_string_literal: true

require "minitest/autorun"
# See test_restore_scripts.rb: the weekly integrity run on vm23 invokes these
# under a C locale, where Ruby reads files as US-ASCII and every read of this
# UTF-8 source raises "invalid byte sequence".
require_relative "../lib/utf8"
require_relative "../config_drift_gate"

# The crontab half of the drift gate, with the shape it must flag and the shape
# it must not.
#
# It exists because the /etc half passed clean while a scheduled job was missing.
# `etc/crontab.vm23:97` has named /usr/local/bin/vps_weekly_integrity.sh for
# weeks; the box has no such line and no such file, and the weekly integrity pass
# has never run. Every file the gate compared matched, so it said clean and meant
# it — it was comparing the wrong thing.
class ConfigDriftGateCrontabTest < Minitest::Test
  REPO = <<~CRON
    # a comment, and a blank line follow
    PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin

    */5 * * * * /usr/local/bin/relayd-watchdog
    */5 * * * * ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh >> /var/log/uptime-check.log 2>&1
    30 3 * * 0 /usr/local/bin/vps_weekly_integrity.sh
  CRON

  # The real live crontab, in the state measured on 2026-09-10: the weekly line
  # was never merged onto the box.
  LIVE_WITHOUT_WEEKLY = <<~CRON
    PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
    */5 * * * * /usr/local/bin/relayd-watchdog
    */5 * * * * ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh >> /var/log/uptime-check.log 2>&1
  CRON

  def test_the_command_is_the_first_absolute_path_not_the_environment_or_the_redirect
    assert_equal(
      %w[/usr/local/bin/relayd-watchdog /usr/local/bin/uptime-check.sh /usr/local/bin/vps_weekly_integrity.sh],
      scheduled_commands(REPO)
    )
  end

  def test_a_path_assignment_is_not_a_scheduled_command
    assert_empty scheduled_commands("PATH=/bin:/usr/local/bin\n")
  end

  # The shape it must flag.
  def test_a_declared_job_the_box_does_not_schedule_is_drift
    cron = crontab_report(REPO, LIVE_WITHOUT_WEEKLY)

    refute cron[:ok], "a job scheduled only in the repo read as clean"
    assert_equal ["/usr/local/bin/vps_weekly_integrity.sh"], cron[:absent]
    assert_empty cron[:extra]
  end

  # The other shape it must flag: a hand-edit on the box that nobody copied back.
  def test_a_job_only_the_box_schedules_is_drift
    cron = crontab_report(REPO, "#{REPO}0 1 * * * /usr/local/bin/hand-added.sh\n")

    refute cron[:ok]
    assert_equal ["/usr/local/bin/hand-added.sh"], cron[:extra]
  end

  # The shape it must not flag, and the one that cost four false alarms on the
  # first run: OpenBSD ships root its own crontab and OPERATOR.sh merges onto it.
  def test_the_base_system_crontab_is_not_drift
    stock = <<~CRON
      0	*	*	*	*	/usr/bin/newsyslog
      30	1	*	*	*	/bin/sh /etc/daily
      30	3	*	*	6	/bin/sh /etc/weekly
    CRON

    cron = crontab_report(REPO, REPO + stock)

    assert cron[:ok], "OpenBSD's own cron lines reported as drift: #{cron[:extra]}"
  end

  # The shape it must not flag. Order and formatting differ because OPERATOR.sh
  # merges rather than overwrites, so only the set of commands is comparable.
  def test_the_same_commands_in_another_order_are_not_drift
    reordered = <<~CRON
      30 3 * * 0 /usr/local/bin/vps_weekly_integrity.sh
      */5 * * * * MAIL_IMG_FMT=png /usr/local/bin/uptime-check.sh >> /var/log/uptime-check.log 2>&1
      */5 * * * * /usr/local/bin/relayd-watchdog
    CRON

    cron = crontab_report(REPO, reordered)

    assert cron[:ok], "a reordered but equivalent crontab reported drift: #{cron[:absent]} #{cron[:extra]}"
    assert_equal 3, cron[:declared]
  end

  # Nothing found and nothing missing are different answers. Reporting every
  # declared job as absent when the crontab could not be read is ten false alarms
  # and the fastest way to teach a reader to skip this section.
  def test_an_unreadable_crontab_skips_rather_than_failing_everything
    cron = crontab_report(REPO, nil)

    assert cron[:ok]
    assert_empty cron[:absent]
    assert_includes cron[:summary], "not readable"
  end

  # The gate is only as good as its mirror. If crontab.vm23 stops parsing, every
  # comparison below it silently compares nothing.
  def test_the_real_tracked_crontab_parses
    tracked = File.join(File.expand_path("..", __dir__), "etc", "crontab.vm23")
    commands = scheduled_commands(File.read(tracked))

    refute_empty commands, "etc/crontab.vm23 parsed to no commands — the check would pass having measured nothing"
    assert(commands.all? { |c| c.start_with?("/") }, "a parsed command is not an absolute path: #{commands.inspect}")
  end
end
