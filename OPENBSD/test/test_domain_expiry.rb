# frozen_string_literal: true

# Domains expire silently and the site stops.
#
# amstrdam.nl served Amsterdam, lapsed, dropped, and was re-registered by someone
# else on 2026-05-18 — noticed 81 days later, by accident. lndon.uk went the same
# way. On 2026-08-07 bsdports.org, a live production site, was 24 hours from
# expiry and nothing in this repo knew.
#
# This reads the committed snapshot rather than the network, so it is fast and
# offline-safe. Refresh the snapshot with:
#
#   ruby OPENBSD/bin/domain_watch.rb --update
#
# It fails on a domain past expiry or inside the warning window, and on a domain
# whose creation date moved — that is what "someone else registered it" looks
# like in whois.

require "minitest/autorun"
require "yaml"
require "date"
require_relative "../bin/domain_watch"

class TestDomainExpiry < Minitest::Test
  SNAPSHOT = File.expand_path("../data/domain_inventory.yml", __dir__)
  RELEASED = File.expand_path("../data/domain_released.yml", __dir__)
  WARN_DAYS = 30

  def setup
    released = File.exist?(RELEASED) ? (YAML.safe_load_file(RELEASED) || {}) : {}
    # A domain we have decided to let go is not an alarm. Recording the decision
    # is the only way this gate can be greened without renewing, and it leaves a
    # reason next to the name rather than a silent skip.
    @released = released.keys
    @rows = YAML.safe_load_file(SNAPSHOT).reject { |domain, _| @released.include?(domain) }
    @today = Date.today
  end

  def expiry_for(row)
    raw = row["expires"]
    return nil if raw.nil? || raw.to_s.strip.empty?

    Date.parse(raw.to_s)
  rescue ArgumentError
    nil
  end

  def test_no_domain_is_past_expiry
    expired = @rows.filter_map do |domain, row|
      date = expiry_for(row)
      next unless date && date < @today

      "#{domain} expired #{date} (#{(@today - date).to_i} days ago)"
    end

    assert_empty expired,
                 "domains past their expiry date. Renew at the registrar and refresh the " \
                 "snapshot with OPENBSD/bin/domain_watch.rb --update, or record the decision to " \
                 "let one go in OPENBSD/data/domain_released.yml. Editing this test is neither:" \
                 "\n  #{expired.join("\n  ")}"
  end

  def test_no_domain_expires_within_the_warning_window
    soon = @rows.filter_map do |domain, row|
      date = expiry_for(row)
      next unless date && date >= @today && date <= @today + WARN_DAYS

      "#{domain} expires #{date} (#{(date - @today).to_i} days)"
    end

    assert_empty soon,
                 "domains expiring within #{WARN_DAYS} days (renew, or record the decision in " \
                 "OPENBSD/data/domain_released.yml):\n  #{soon.join("\n  ")}"
  end

  # A snapshot that silently empties would make both assertions above pass.
  def test_the_snapshot_still_holds_domains
    assert_operator @rows.size, :>, 40, "snapshot holds only #{@rows.size} domains"
    known = @rows.count { |_, row| row["state"] == "registered" }
    assert_operator known, :>, 10, "only #{known} domains resolved to a registration record"
  end

  # A lookup must be bounded and must not go through a shell. This asserted a
  # source spelling naming /usr/bin/timeout instead, which held the tool to a
  # binary macOS does not have — so --update ran only on vm23 and the snapshot
  # this suite reads went three weeks stale. The behaviour was right and the
  # check was measuring how it was written.
  #
  # What matters, held two ways: no shell form anywhere, and a slow child is
  # actually killed. The second runs a real process, because a timeout that
  # never fires looks exactly like a fast network.
  def test_a_lookup_is_bounded_and_never_goes_through_a_shell
    source = File.read(File.expand_path("../bin/domain_watch.rb", __dir__))
    # Code only. The first draft of this matched a backtick inside the comment
    # explaining why backticks are wrong — the instrument reading its own
    # documentation and reporting it as the defect.
    code = source.lines.reject { |line| line.strip.start_with?("#") }.join

    refute_match(/`[^`\n]*\b(?:whois|curl|timeout)\b/, code, "a lookup went back through a shell")
    refute_match(/\bsystem\(/, code, "a lookup was handed to a shell")
  end

  # The registry's own words decide the state. Both patterns are /x so they can
  # wrap, and /x drops every literal space: "is free" compiled to "isfree", so
  # rottrdam.nl answering "rottrdam.nl is free" was filed unknown with that line
  # as its note. Each phrase is held against the answer it has to read.
  def whois_answer(body)
    watch = Deploy::DomainWatch
    original = watch.method(:capture_bounded)
    watch.define_singleton_method(:capture_bounded) { |*_argv, **_opts| body }
    watch.whois_query("example.nl")
  ensure
    watch.define_singleton_method(:capture_bounded, original)
  end

  def test_every_available_phrase_reads_as_available
    ["example.nl is free", "No match for \"EXAMPLE.NL\".", "NOT FOUND", "No entries found",
     "Domain example.nl is available", "No Data Found", "Object does not exist",
     "example.nl not registered", "Status: free"].each do |body|
      assert_equal "available", whois_answer(body)["state"], "#{body.inspect} did not read as available"
    end
  end

  def test_every_registered_phrase_reads_as_registered
    ["example.nl\nRegistered on: 2020-01-01", "example.nl\nCreation Date: 2020-01-01",
     "example.nl\nName Server: ns.example.nl", "example.nl\nDomain nameservers:\n ns.example.nl",
     "example.nl\nRegistrar: Example"].each do |body|
      assert_equal "registered", whois_answer(body)["state"], "#{body.inspect} did not read as registered"
    end
  end

  def test_a_hung_lookup_is_killed_rather_than_waited_on
    started = Time.now
    out = Deploy::DomainWatch.capture_bounded("sleep", "30", seconds: 1)
    elapsed = Time.now - started

    assert_operator elapsed, :<, 10, "capture_bounded waited #{elapsed.round(1)}s against a 1s bound"
    assert_equal "", out.strip
  end
end
