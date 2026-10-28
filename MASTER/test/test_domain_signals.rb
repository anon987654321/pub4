# frozen_string_literal: true

require_relative "test_helper"
require_relative "../../OPENBSD/lib/domain_signals"

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
    assert_includes s[:relay_residual], "alfa.brgen.no"
    assert_includes s[:relay_residual], "thor.brgen.no"
    assert_includes s[:registered_not_owned], "amstrdam.nl"
    assert_empty s[:owned_missing_from_inventory]
  end

  def test_status_is_silent_when_signals_empty
    Dir.mktmpdir do |dir|
      assert_empty DomainSignals.status_lines(dir)
    end
  end
end
