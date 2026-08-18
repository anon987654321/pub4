# frozen_string_literal: true

require "minitest/autorun"
# See test_restore_scripts.rb: the weekly integrity run on vm23 invokes these
# under a C locale, where Ruby reads files as US-ASCII and every read of this
# UTF-8 source raises "invalid byte sequence".
require_relative "../lib/utf8"

# etc/crontab.vm23 is the tracked half of root's crontab, and OPERATOR.sh's
# install_tracked_crontab merges it onto the box. Both halves can be complete
# and correct while the job is not scheduled anywhere, which is the failure this
# file exists for.
#
# Measured 2026-08-18: uptime-check.sh was in crontab.vm23 and in
# usr/local/bin/ since 2026-08-12, and was on neither the box's crontab nor its
# filesystem. Nothing was missing from either file, so nothing read as wrong.
# The merge loop had skipped the line — correctly, since the wrapper was not
# installed and cron would otherwise mail root every five minutes — but
# silently, so the skip taught nobody anything.
class TrackedCrontabTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TRACKED = File.join(ROOT, "etc", "crontab.vm23")
  OPERATOR = File.join(ROOT, "OPERATOR.sh")

  def crontab_source = @crontab_source ||= File.read(TRACKED)

  def operator_source = @operator_source ||= File.read(OPERATOR)

  # A cron line is five time fields then the command.
  def scheduled_commands
    crontab_source.each_line.filter_map do |line|
      next if line.strip.empty? || line.lstrip.start_with?("#")

      command = line.split[5]
      command if command&.start_with?("/")
    end.uniq
  end

  def test_the_tracked_crontab_actually_schedules_something
    refute_empty scheduled_commands,
                 "no cron lines parsed out of etc/crontab.vm23 — this test would pass having measured nothing"
  end

  # The repo may not schedule a command it does not ship. If it does, the merge
  # loop skips the line on every run and the job is tracked but never installed.
  def test_every_scheduled_command_is_shipped_by_this_repo
    missing = scheduled_commands.reject do |command|
      base = File.basename(command)
      File.file?(File.join(ROOT, "usr", "local", "bin", base)) || File.file?(File.join(ROOT, base))
    end

    assert_empty missing,
                 "etc/crontab.vm23 schedules commands this repo does not ship, so " \
                 "install_tracked_crontab will skip them forever:\n#{missing.join("\n")}"
  end

  # install(1) sets the mode on the box, but a non-executable source is a sign
  # the wrapper was written and never wired, and it is free to check here.
  def test_shipped_cron_wrappers_are_executable_in_the_repo
    not_executable = scheduled_commands.filter_map do |command|
      base = File.basename(command)
      path = [File.join(ROOT, "usr", "local", "bin", base), File.join(ROOT, base)].find { |p| File.file?(p) }
      path if path && !File.executable?(path)
    end

    assert_empty not_executable, "tracked cron wrappers are not executable:\n#{not_executable.join("\n")}"
  end

  # cron(8) runs with PATH=/bin:/sbin:/usr/bin:/usr/sbin. Every interpreter this
  # box uses is in /usr/local/bin, so without this line an `#!/usr/bin/env ruby`
  # job fails at exec once per tick, forever, one unread line at a time. Four of
  # five jobs here had never run for exactly that reason.
  def test_the_crontab_sets_a_path_that_includes_usr_local_bin
    path_line = crontab_source.each_line.find { |l| l.start_with?("PATH=") }

    refute_nil path_line, "etc/crontab.vm23 no longer sets PATH"
    assert_includes path_line, "/usr/local/bin"
  end

  def test_operator_rewrites_the_path_rather_than_appending_it
    assert_includes operator_source, "grep -m1 '^PATH=' $tracked",
                    "install_tracked_crontab no longer carries the PATH line, which the merge loop cannot"
  end

  # The point of this file. Skipping is correct; skipping quietly is what let a
  # tracked job go unscheduled for six days.
  def test_a_skipped_cron_line_says_so
    loop_body = operator_source[/while IFS= read -r line; do.*?done < \$tracked/m]

    refute_nil loop_body, "install_tracked_crontab's merge loop moved or changed shape"
    assert_match(/! -x \$cmdpath/, loop_body, "the merge loop no longer checks the command is executable")
    assert_match(/log WARN .*not installed/, loop_body,
                 "install_tracked_crontab skips a tracked cron job without logging it")
  end
end
