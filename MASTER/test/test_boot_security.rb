# frozen_string_literal: true

require "minitest/autorun"
require "master"
require_relative "../lib/cli/boot_banner"

class BootSecurityLinesTest < Minitest::Test
  def test_boot_describes_real_security_layers
    lines = Master::CLI::BootBanner.security_lines
    assert_match(/\Asecurity0 at master0: .*\badmission\b/, lines.first)
    # pledge is claimed only on OpenBSD; elsewhere the unit says it is not configured.
    pledge = Master::Ground::Pledge.openbsd? ? "staged reduction" : "not configured"
    assert_includes lines, "pledge0 at security0: #{pledge}"
    assert_includes lines.join("\n"), "transaction-backed self-change"
    assert_includes lines.join("\n"), "proposal-only"
  end
end
