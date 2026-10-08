# frozen_string_literal: true

require "minitest/autorun"
require "active_support/all"
require_relative "../shared/app/services/shared/link_converter"

# Why this exists: amber showed affiliate links and earned nothing from them, for
# two independent reasons. The feed client it asked for lived in brgen's process,
# and its saved links were emitted verbatim — no website id, so a converting click
# paid nobody. This module is the second half, in the engine so every app can use
# one implementation of the attribution rule.
class LinkConverterTest < Minitest::Test
  LC = Shared::LinkConverter
  TARGET = "https://shop.example/coat?size=m"

  def setup
    @saved = ENV.to_hash.slice("TRADEDOUBLER_WEBSITE_ID", "TRADEDOUBLER_SERVER_SIDE_WRAP")
  end

  def teardown
    %w[TRADEDOUBLER_WEBSITE_ID TRADEDOUBLER_SERVER_SIDE_WRAP].each { |key| ENV.delete(key) }
    @saved.each { |key, value| ENV[key] = value }
  end

  def configured!(wrap: true)
    ENV["TRADEDOUBLER_WEBSITE_ID"] = "12345"
    ENV["TRADEDOUBLER_SERVER_SIDE_WRAP"] = "1" if wrap
  end

  def test_unconfigured_changes_nothing
    assert_equal TARGET, LC.wrap(TARGET)
    refute LC.configured?
    assert_nil LC.remote_script_url
  end

  # The flag is the point: the verified attribution path is the vendor's own
  # script, and this hand-built deep link ships off until a live click has gone
  # through it. A wrong grammar is a broken link, not an unattributed one.
  def test_server_side_wrapping_is_off_until_asked_for
    configured!(wrap: false)

    assert LC.configured?, "website id alone must not enable wrapping"
    assert_equal TARGET, LC.wrap(TARGET)
  end

  def test_wrapping_carries_the_website_id_and_the_target
    configured!
    wrapped = LC.wrap(TARGET)

    assert_includes wrapped, "a(12345)"
    assert_includes wrapped, "url("
    assert_includes wrapped, "shop.example"
    assert wrapped.start_with?(Shared::LinkConverter::ENDPOINT)
  end

  # The bug this pins, found by running the code rather than reading it: epi was
  # appended with URI.encode_www_form, which re-encoded the parentheses of
  # a(…)url(…) into `a%2812345%29=` — a link that tracks nothing and goes nowhere.
  def test_epi_is_a_segment_not_a_query_parameter
    configured!
    wrapped = LC.wrap(TARGET, epi: LC.epi_for(surface: "amber", post_id: 7))

    assert_includes wrapped, "a(12345)", "the website id segment must survive epi"
    assert_includes wrapped, "epi(", "epi belongs in a segment"
    refute_includes wrapped, "a%28", "parentheses must not be percent-encoded"
    refute_includes wrapped, "=&", "this is not a query string"
  end

  # Double-wrapping an owner-pasted tracked URL destroys the tracking that was
  # already on it, which is worse than leaving it alone.
  def test_an_already_tracked_url_is_left_alone
    configured!
    tracked = "https://clk.tradedoubler.com/click?p=1&url=x"

    assert_equal tracked, LC.wrap(tracked)
    assert LC.already_tracked?(tracked)
    refute LC.already_tracked?(TARGET)
  end

  def test_a_malformed_url_does_not_raise
    configured!

    refute LC.already_tracked?("http://[not a url")
    assert_equal "", LC.wrap("")
  end

  # Nil rather than an empty string, so a caller can skip the parameter instead of
  # sending one that says nothing.
  def test_epi_is_nil_when_there_is_nothing_to_say
    assert_nil LC.epi_for
    assert_equal "city:bergen|surface:amber", LC.epi_for(city: "bergen", surface: "amber")
  end

  # Ad blockers target tradedoubler.com by hostname, so a first-party copy is the
  # one that survives — but an app with no sync job of its own must still get a
  # script, because remote-and-sometimes-blocked beats absent.
  def test_script_source_prefers_a_local_copy_and_falls_back_to_remote
    configured!(wrap: false)

    assert_equal "https://link.tradedoubler.com/lc?a(12345)", LC.script_src("/no/such/public")

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "js"))
      File.write(File.join(dir, Shared::LinkConverter::SCRIPT_RELATIVE_PATH), "// script")

      assert_equal "/js/td-lc.js", LC.script_src(dir)
    end
  end

  def test_sync_refuses_without_a_website_id
    refute LC.sync!(local_path: "/tmp/should-not-be-written-#{Process.pid}")
  end
end

require "tmpdir"
require "fileutils"
