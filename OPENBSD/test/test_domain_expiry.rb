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
                 "domains past their expiry date. Renew at the registrar, then refresh the " \
                 "snapshot with OPENBSD/bin/domain_watch.rb --update:\n  #{expired.join("\n  ")}"
  end

  def test_no_domain_expires_within_the_warning_window
    soon = @rows.filter_map do |domain, row|
      date = expiry_for(row)
      next unless date && date >= @today && date <= @today + WARN_DAYS

      "#{domain} expires #{date} (#{(date - @today).to_i} days)"
    end

    assert_empty soon,
                 "domains expiring within #{WARN_DAYS} days:\n  #{soon.join("\n  ")}"
  end

  # A snapshot that silently empties would make both assertions above pass.
  def test_the_snapshot_still_holds_domains
    assert_operator @rows.size, :>, 40, "snapshot holds only #{@rows.size} domains"
    known = @rows.count { |_, row| row["state"] == "registered" }
    assert_operator known, :>, 10, "only #{known} domains resolved to a registration record"
  end

  # Source-level: a shell form like `timeout 15 <cmd>` needs a cron PATH
  # carrying GNU timeout and parses the zone name in a shell. The Open3 argv
  # form needs neither; a regression back to the shell form is invisible until
  # a whois hangs or a name is interpolated.
  def test_whois_runs_through_open3_and_usr_bin_timeout
    source = File.read(File.expand_path("../bin/domain_watch.rb", __dir__))
    refute_match(/`timeout\s/, source, "whois went back through a shell timeout")
    assert_includes source, 'Open3.capture2e("/usr/bin/timeout"'
  end
end
