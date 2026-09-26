# frozen_string_literal: true

require "minitest/autorun"
require "date"
require "fileutils"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
# See test_restore_scripts.rb: the weekly integrity run on vm23 invokes these
# under a C locale, where Ruby reads files as US-ASCII and every read of this
# UTF-8 source raises "invalid byte sequence".
require_relative "../lib/utf8"
require_relative "../gates/config_drift_gate"
require_relative "../lib/operator_source"

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

  def operator_source = @operator_source ||= Deploy::OperatorSource.read(OPERATOR)

  # One parser for a cron line, the drift gate's, so the shapes it must and must
  # not read (an env prefix, a redirect, a PATH line) have one set of fixtures, in
  # test_config_drift_gate.rb, and a new cron line is proved once.
  def scheduled = scheduled_commands(crontab_source)

  def test_env_prefixed_lines_are_parsed
    assert_includes scheduled, "/usr/local/bin/uptime-check.sh" if crontab_source.include?("uptime-check.sh")
  end

  def test_the_tracked_crontab_actually_schedules_something
    refute_empty scheduled,
                 "no cron lines parsed out of etc/crontab.vm23 — this test would pass having measured nothing"
  end

  # The repo may not schedule a command it does not ship. If it does, the merge
  # loop skips the line on every run and the job is tracked but never installed.
  def test_every_scheduled_command_is_shipped_by_this_repo
    # Shipped means copied with usr/local/bin/, or named by an `install` line in
    # OPERATOR.sh whose source is in the tree. Where that source sits is the
    # install line's business, so the test reads the line rather than guessing a
    # directory.
    installed = operator_source.scan(%r{install\s[^\n]*?"\$\{SCRIPT_DIR\}/([\w./-]+)"\s+(/usr/local/bin/[\w.-]+)})
                               .select { |source, _| File.file?(File.join(ROOT, source)) }
                               .map(&:last)
    missing = scheduled.reject do |command|
      File.file?(File.join(ROOT, "usr", "local", "bin", File.basename(command))) || installed.include?(command)
    end

    assert_empty missing,
                 "etc/crontab.vm23 schedules commands this repo does not ship, so " \
                 "install_tracked_crontab will skip them forever:\n#{missing.join("\n")}"
  end

  # install(1) sets the mode on the box, but a non-executable source is a sign
  # the wrapper was written and never wired, and it is free to check here.
  def test_shipped_cron_wrappers_are_executable_in_the_repo
    not_executable = scheduled.filter_map do |command|
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

# The scheduled jobs themselves, run against fixtures rather than read. Each one
# is run only where it cannot touch a real box: rcctl present means vm23, and a
# test there would reach the certificates and the zones.
class ScheduledJobsTest < Minitest::Test
  BIN = File.expand_path("../usr/local/bin", __dir__)

  def setup
    skip "on an OpenBSD box these would act on live state" if File.executable?("/usr/sbin/rcctl")
    @tmp = Dir.mktmpdir("jobs")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp
  end

  def write(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # ---- nsd-resign -----------------------------------------------------------

  def rrsig(expiry) = "brgen.no. 3600 IN RRSIG SOA 13 2 3600 #{expiry} 20260901000000 4242 brgen.no. c2ln\n"

  def resign(*args)
    Open3.capture2e({ "NSD_ZONES_DIR" => @tmp }, RbConfig.ruby, File.join(BIN, "nsd-resign"), *args)
  end

  def test_nsd_resign_reads_the_earliest_signature_expiry
    load File.join(BIN, "nsd-resign")
    signed = write("brgen.no.zone.signed", rrsig("20261201000000") + rrsig("20261015120000"))

    assert_equal Date.new(2026, 10, 15), expiry_date(signed)
  end

  # Garbage has no expiry, and no expiry means re-sign, never "still valid".
  def test_nsd_resign_treats_an_unparseable_signed_zone_as_due
    write("brgen.no.zone", "$ORIGIN brgen.no.\n")
    write("Kbrgen.no.+013+04242.key", "brgen.no. IN DNSKEY 257 3 13 AAAA\n")
    write("brgen.no.zone.signed", "\x00\xFF not a zone")
    out, status = resign

    assert_includes out, "brgen.no expires unknown — resigning"
    refute status.success?, "no ldns-signzone here, so the zone must count as failed: #{out}"
    assert_includes out, "FAIL 1 zone(s) not signed: brgen.no"
  end

  def test_nsd_resign_leaves_a_fresh_zone_alone
    write("brgen.no.zone", "$ORIGIN brgen.no.\n")
    write("Kbrgen.no.+013+04242.key", "brgen.no. IN DNSKEY 257 3 13 AAAA\n")
    write("brgen.no.zone.signed", rrsig((Date.today + 25).strftime("%Y%m%d000000")))
    out, status = resign

    assert status.success?, out
    assert_includes out, "all 1 zones valid — nothing to do"
  end

  def test_nsd_resign_with_no_keyed_zones_fails
    write("brgen.no.zone", "$ORIGIN brgen.no.\n")
    out, status = resign

    refute status.success?
    assert_includes out, "FAIL no signable zones"
  end

  # ---- renew-certs.sh -------------------------------------------------------

  def renew(conf)
    env = { "RENEW_CERTS_ACME_CONF" => write("acme-client.conf", conf), "RENEW_CERTS_SSL_DIR" => File.join(@tmp, "ssl") }
    Open3.capture3(env, "zsh", File.join(BIN, "renew-certs.sh"))
  end

  # CONFIGURED ∩ HELD: a held name acme-client cannot renew is skipped, a
  # configured name with no certificate is never attempted, smtp is smtpd's own.
  def test_renew_certs_renews_only_what_is_both_held_and_configured
    %w[brgen.no amberapp.art ai.brgen.no smtp].each { |name| write("ssl/#{name}.crt", "") }
    out, _, status = renew(%(domain "brgen.no" {\n}\ndomain "amberapp.art" {\n}\ndomain "lapsed.uk" {\n}\n))

    assert status.success?, out
    assert_includes out, "renewing 2 of 3 held certificate(s): amberapp.art brgen.no"
    assert_includes out, "held but not in"
    assert_includes out, "skipping: ai.brgen.no"
    refute_includes out, "lapsed.uk"
    assert_includes out, "nothing renewed, leaving relayd alone"
  end

  def test_renew_certs_refuses_when_nothing_held_is_configured
    write("ssl/ai.brgen.no.crt", "")
    _, err, status = renew(%(domain "brgen.no" {\n}\n))

    assert_equal 1, status.exitstatus
    assert_includes err, "refusing to run"
  end

  # ---- the load-waiting wrappers --------------------------------------------

  # No ruby34 here, so the load never reads low: every tick waits and the run
  # ends in a skip, exit 0, without reaching an app.
  def test_prune_guests_waits_every_tick_then_skips
    env = { "PRUNE_GUESTS_LOAD_CEILING" => "0", "PRUNE_GUESTS_WAIT_TICKS" => "2", "PRUNE_GUESTS_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "prune-guests.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2, "the wait loop did not sleep once per tick"
    assert_match(/skipped: load stayed over 0 for 0 minutes/, out)
    refute_match(/FAILED|removed=/, out)
  end

  def test_drain_jobs_waits_every_tick_then_skips
    env = { "DRAIN_JOBS_LOAD_CEILING" => "0", "DRAIN_JOBS_WAIT_TICKS" => "2", "DRAIN_JOBS_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "drain-jobs.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2
    assert_match(/skipped: load stayed over 0/, out)
  end

  def test_declutter_hygiene_waits_every_tick_then_skips
    env = { "DECLUTTER_HYGIENE_LOAD_CEILING" => "0", "DECLUTTER_HYGIENE_WAIT_TICKS" => "2",
            "DECLUTTER_HYGIENE_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "declutter-hygiene.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2, "the wait loop did not sleep once per tick"
    assert_match(/skipped: load stayed over 0 for 0 minutes/, out)
    refute_match(/FAILED|expired_challenges=/, out)
  end

  def test_ports_import_waits_every_tick_then_skips
    env = { "PORTS_IMPORT_LOAD_CEILING" => "0", "PORTS_IMPORT_WAIT_TICKS" => "2",
            "PORTS_IMPORT_TICK_SECONDS" => "1" }
    started = Time.now
    out, status = Open3.capture2e(env, "sh", File.join(BIN, "ports-import.sh"))

    assert status.success?, out
    assert_operator Time.now - started, :>=, 2, "the wait loop did not sleep once per tick"
    assert_match(/skipped: load stayed over 0 for 0 minutes/, out)
    refute_match(/FAILED|ports_count=/, out)
  end

  # A shed app is left shed: nothing listening is skipped silently, not warmed
  # and not logged as a failure every ten minutes.
  def test_keep_warm_skips_a_target_that_is_not_listening
    ports = [38_182, 61_352]
    skip "an app is listening locally" if ports.any? { |port| (TCPSocket.new("127.0.0.1", port).close || true) rescue false }
    out, status = Open3.capture2e("ksh", File.join(BIN, "keep-warm.sh"))

    assert status.success?, out
    assert_empty out.strip
  end
end
