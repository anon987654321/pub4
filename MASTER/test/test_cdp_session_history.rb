# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../gates/support/cdp_session", __dir__)

# Chrome has no Page.goBack; CdpSession#back and #forward move through
# Page.getNavigationHistory. This proves it in a real headless Chrome and is
# skipped where Chrome is absent.
class TestCdpSessionHistory < Minitest::Test
  def with_two_pages
    skip "no headless Chrome" unless Deploy::CdpSession.available?
    Dir.mktmpdir("cdp-history") do |dir|
      %w[a b].each { |name| File.write(File.join(dir, "#{name}.html"), "<html><body><h1>#{name}</h1></body></html>") }
      Deploy::CdpSession.open do |cdp|
        yield cdp, "file://#{File.join(dir, "a.html")}", "file://#{File.join(dir, "b.html")}"
      end
    end
  end

  def test_back_and_forward_return_to_the_previous_and_next_page
    with_two_pages do |cdp, a, b|
      cdp.navigate(a)
      cdp.navigate(b)
      assert_equal b, cdp.evaluate("location.href")

      cdp.back
      assert_equal a, cdp.evaluate("location.href")

      cdp.forward
      assert_equal b, cdp.evaluate("location.href")
    end
  end

  # Whether Chrome keeps its initial about:blank entry varies, so the edge only
  # has to be safe: stepping past the first entry never raises or leaves history.
  def test_stepping_past_the_first_entry_is_safe
    with_two_pages do |cdp, a, _b|
      cdp.navigate(a)
      3.times { cdp.back }
      assert_includes [a, "about:blank"], cdp.evaluate("location.href")
      3.times { cdp.forward }
      assert_equal a, cdp.evaluate("location.href")
    end
  end
end
