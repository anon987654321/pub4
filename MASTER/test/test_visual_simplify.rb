# frozen_string_literal: true

require_relative "test_helper"
require "erb"
require "tmpdir"
require_relative "../lib/fix/visual_simplify"
require File.expand_path("../checks/support/capture_engine", __dir__)
require File.expand_path("../checks/support/pixel_match", __dir__)

# The simplify stage on a fixture page: a redundant wrapper, a duplicate variant and a literal
# that a token declares are removed with lower counts and no changed pixel; a simplification that
# moves pixels is routed to the reviewer, and one that lowers no count is refused.
class TestVisualSimplify < Minitest::Test
  SIMPLIFY = Master::Fix::VisualSimplify
  CSS = <<~CSS
    :root { --ink: #111111; }
    body { margin: 0; font: 16px Arial, sans-serif; }
    .card { padding: 8px; color: #111111; }
    .card-copy { padding: 8px; color: #111111; }
  CSS
  HTML = %(<main><div><section class="card">Hei</section></div><section class="card-copy">Hallo</section></main>)

  # The fixture page: its stylesheet, then its markup.
  PAGE = %(<link rel="stylesheet" href="data:text/css,%s">%s)

  def test_the_reducer_unwraps_merges_and_tokenises
    reduced = SIMPLIFY.reduce(html: HTML, css: CSS)

    refute_includes reduced[:html], "<div>"
    assert_includes reduced[:css], ".card, .card-copy { padding: 8px; color: var(--ink); }"
    assert_includes reduced[:css], "--ink: #111111;"
    assert_operator SIMPLIFY.counts(**reduced)[:total], :<, SIMPLIFY.counts(html: HTML, css: CSS)[:total]
  end

  def test_no_count_falling_is_refused_whatever_the_pixels
    same = SIMPLIFY.counts(html: HTML, css: CSS)

    assert_equal :refused, SIMPLIFY.verdict(before: same, after: same, changed_pixels: 0)
  end

  # Rendered in Chrome: the reduced page paints the same pixels, so it is accepted; the same
  # reduction plus a spacing change paints differently, so it goes to review.
  def test_a_reduction_with_no_changed_pixel_is_accepted_and_a_visible_one_is_reviewed
    skip "no Chrome here" unless Deploy::CdpSession.available?

    reduced = SIMPLIFY.reduce(html: HTML, css: CSS)
    moved = reduced.merge(css: reduced[:css].sub("padding: 8px", "padding: 16px"))
    Dir.mktmpdir do |dir|
      shots = render({ "before" => { html: HTML, css: CSS }, "reduced" => reduced, "moved" => moved }, dir)
      before = SIMPLIFY.counts(html: HTML, css: CSS)

      assert_equal :accepted, verdict(before, { page: reduced, pixels: changed(shots, "reduced") })
      assert_equal :review, verdict(before, { page: moved, pixels: changed(shots, "moved") })
    end
  end

  def verdict(before, page)
    SIMPLIFY.verdict(before:, after: SIMPLIFY.counts(**page[:page]), changed_pixels: page[:pixels])
  end

  def changed(shots, name)
    compared = Deploy::PixelMatch.compare(baseline_path: shots.fetch("before"), current_path: shots.fetch(name))
    compared[:pixel_diff_count]
  end

  def render(pages, dir)
    cdp = Deploy::CdpSession.new
    cdp.start
    cdp.viewport(390, 200, mobile: true)

    pages.to_h do |name, page|
      markup = format(PAGE, ERB::Util.url_encode(page[:css]), page[:html])
      cdp.navigate("data:text/html,#{ERB::Util.url_encode(markup)}")
      [name, Deploy::CaptureEngine.still_screenshot(cdp, File.join(dir, "#{name}.png"))[:path]]
    end
  ensure
    cdp&.close
  end
end
