# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/master"

class TestDomainCommands < Minitest::Test
  def test_dispatch_domain_playlist
    out = Master::CLI::CommandRegistry.dispatch_domain(Master::ROOT, ctx: { args: "playlist" })
    assert_includes out, "playlist"
    assert_includes out, "rails-multi-tenant"
  end

  def test_help_domain
    text = Master::CLI::CommandRegistry.help_text("domain")
    refute_includes text, "unknown"
    assert_includes text, "/domain"
  end
end
