# frozen_string_literal: true

require_relative "test_helper"
# The MASTER runtime loads its own copy (lib/operator/domain_signals.rb) so no
# MASTER/lib file requires a sibling tree's implementation; OPENBSD/lib keeps
# the canonical original and the parity test below holds the two identical.
require_relative "../lib/operator/domain_signals"

class TestDomainSignals < Minitest::Test
  def setup
    @root = File.expand_path("../..", __dir__)
  end

  def test_status_lines_only_report_skew
    lines = DomainSignals.status_lines(@root)
    lines.each do |line|
      assert_match(/\A(domains|relay): /, line)
    end
  end

  def test_scan_finds_known_residuals_in_this_repo
    s = DomainSignals.scan(@root)
    # thor.brgen.no / alfa.brgen.no (the retired static exports) were removed
    # from relayd.conf on 2026-10-28 together with RAILS/__other, so the relay
    # carries no ghosts: every Host match is a known name.
    assert_empty s[:relay_residual]
    assert_includes s[:registered_not_owned], "amstrdam.nl"
    assert_empty s[:owned_missing_from_inventory]
  end

  def test_status_is_silent_when_signals_empty
    Dir.mktmpdir do |dir|
      assert_empty DomainSignals.status_lines(dir)
    end
  end

  def test_the_master_copy_matches_the_openbsd_original_byte_for_byte
    canonical = File.expand_path("../../OPENBSD/lib/domain_signals.rb", __dir__)
    copy = File.expand_path("../lib/operator/domain_signals.rb", __dir__)
    assert FileUtils.compare_file(canonical, copy),
           "lib/operator/domain_signals.rb drifted from OPENBSD/lib/domain_signals.rb; copy the original over it"
  end
end
