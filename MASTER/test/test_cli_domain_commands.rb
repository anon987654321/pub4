# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestDomainCommands < Minitest::Test
  def test_dispatch_domain_playlist
    out = Master::CLI::CommandRegistry.dispatch_domain(Master::ROOT, ctx: { args: "playlist" })
    assert_includes out, "playlist"
    assert_includes out, "rails-multi-tenant"
  end

  def test_help_does_not_advertise_domain
    text = Master::CLI::CommandRegistry.help_text("domain")
    assert_includes text, "unknown command"
  end
end
