# frozen_string_literal: true

require "minitest/autorun"
require "master"
require_relative "../lib/cli/boot_banner"

class BootSecurityLinesTest < Minitest::Test
  def test_boot_describes_real_security_layers
    lines = Master::CLI::BootBanner.security_lines
    assert_includes lines.join("\n"), "constitutional admission"
    assert_includes lines.join("\n"), "staged reduction"
    assert_includes lines.join("\n"), "transaction-backed self-change"
    assert_includes lines.join("\n"), "proposal-only"
  end
end
