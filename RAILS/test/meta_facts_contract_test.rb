# frozen_string_literal: true

require "minitest/autorun"

# These contracts keep metadata as facts with real element boundaries rather
# than words separated by a punctuation glyph. Rendering and spacing are
# separate concerns: the stylesheet owns the gap; templates own the meaning.
class MetaFactsContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  def test_checkbox_toggle_hits_the_shared_tap_floor_without_growing_its_painted_track
    css = read("__shared/app/assets/stylesheets/components/_fields.scss")
    assert_match(/input\[type="checkbox"\]\.toggle\s*\{[^}]*height: var\(--tap-min\);[^}]*border-block: 9px solid transparent;[^}]*background-clip: padding-box;/m, css)
  end

  def test_shared_fact_row_uses_flex_gap
    css = read("__shared/app/assets/stylesheets/_shared_coverage_fills.scss")
    assert_match(/\.meta-facts\s*\{[^}]*display: flex;[^}]*column-gap: var\(--space-2\);[^}]*row-gap: var\(--space-1\);/m, css)
  end

  def test_shared_feed_card_accepts_fact_arrays_and_preserves_legacy_strings
    template = read("__shared/app/views/shared/_feed_card.html.erb")
    assert_includes template, "local_assigns[:meta].is_a?(Array)"
    assert_includes template, "<span><%= fact %></span>"
    assert_match(/<% else %>\s*<%= local_assigns\[:meta\] %>/m, template)
    assert_includes read("brgen_marketplace/engines/takeaway/app/views/takeaway/orders/_order.html.erb"), "meta: ["
  end

  def test_fact_views_keep_independent_metadata_elements
    paths = %w[
      brgen/app/views/users/show.html.erb
      brgen/app/views/partner/memberships/show.html.erb
      brgen_maps/app/views/maps/places/_card.html.erb
      brgen_marketplace/app/views/marketplace/listings/_buybox.html.erb
      brgen_radio/playlist/app/views/playlist/sets/show.html.erb
      brgen_dating/app/views/dating/profiles/show.html.erb
    ]
    paths.each do |path|
      assert_includes read(path), 'class="meta-facts"', "#{path} must render facts as separate elements"
    end

    buybox = read("brgen_marketplace/app/views/marketplace/listings/_buybox.html.erb")
    assert_includes buybox, "condition_facts.each do |fact|"
    crossings = read("brgen_dating/app/views/dating/path_crossings/index.html.erb")
    assert_includes crossings, 'class="meta-facts"'
    refute_includes crossings, " · <%= time_ago_in_words(crossing.crossed_at) %>"
  end

  def test_post_card_bylines_do_not_embed_separator_glyphs
    template = read("__shared/app/views/shared/_post_card.html.erb")
    refute_includes template, " · <span class=\"feed-post-place\""
    refute_includes template, 'class="feed-card-time">· '
    assert_includes template, '<% if meta.present? %><p><%= meta %></p><% end %>'
  end
end
