# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/lib/pub4/asset_url_lint"

# The gap css_coverage_lint left. It measures class names in both directions and
# never looks inside a declaration, so no committed tool read `url()` — and the
# audit that produced it checked `image_tag` and `asset_path`, the reference forms
# that fail loudly, and skipped the one that fails silently.
#
# What it found on the first run was live: amber served a lightgallery.css whose
# icon font 404'd.
class AssetUrlLintTest < Minitest::Test
  L = Pub4::AssetUrlLint

  def test_no_kind_exceeds_its_baseline
    exceeded = L.over_baseline

    assert_empty exceeded, exceeded.join("; ")
  end

  def test_baselines_are_not_stale
    counts = L.counts

    L::BASELINES.each do |kind, baseline|
      assert_equal baseline, counts.fetch(kind),
                   "#{kind} is at #{counts.fetch(kind)} against #{baseline} — lower it in asset_url_lint.rb"
    end
  end

  # The regression this lint was written for. amber's layout links
  # `/lightgallery.css`, amber has no copy, so it is served shared's — and shared's
  # `../fonts/lg.*` resolved to files that existed only under brgen/public.
  # Asserted through the resolver rather than by listing files, so moving the
  # assets to a different served root still passes and deleting them fails.
  def test_amber_can_resolve_the_lightgallery_icon_font
    sheet = File.join(L::RAILS_ROOT, "shared/public/lightgallery.css")

    %w[../fonts/lg.woff2 ../fonts/lg.woff ../images/loading.gif].each do |ref|
      assert L.satisfied_everywhere?(ref, sheet),
             "#{ref} must resolve for every app that links shared's lightgallery.css, not just brgen"
    end
  end

  # An app-owned stylesheet may rely on its own public/ root; a shared one may not,
  # because it is served to three apps. This is the distinction that turns a
  # file-existence check into a measurement.
  def test_a_shared_sheet_needs_the_file_where_every_app_can_see_it
    shared_sheet = File.join(L::RAILS_ROOT, "shared/app/assets/stylesheets/_fonts.scss")
    brgen_sheet = File.join(L::RAILS_ROOT, "brgen/app/assets/stylesheets/_fonts_brand.scss")

    assert L.satisfied_everywhere?("/fonts/JetBrainsMonoNerdFont-Regular.woff2", shared_sheet)
    # Bricolage, not Inter. Inter was the example here until brgen stopped naming
    # the family — the wordmark moved to --font-brand and the body face to
    # system-ui, so the five cuts became five files no rule could pull and were
    # deleted. Bricolage Grotesque is the marketplace display face, still
    # vendored in brgen/public only, which is the property under test.
    assert L.satisfied_everywhere?("/fonts/bricolage-grotesque-latin-wght-normal.woff2", brgen_sheet)
    refute L.satisfied_everywhere?("/fonts/bricolage-grotesque-latin-wght-normal.woff2", shared_sheet),
           "bricolage lives only in brgen/public — a shared stylesheet asking for it would 404 on amber"
  end

  # My own first run reported PP Neue Montreal in five weights because `expand`
  # read every `@each $w` in the file rather than the enclosing one, and
  # _fonts_brand.scss has two over different weight lists. Two of the five names
  # appear in no stylesheet at all. A lint that invents a filename cannot be
  # trusted about the ones it did not invent.
  def test_each_expansion_is_scoped_to_the_enclosing_loop
    body = <<~SCSS
      @each $w in (400, 500) {
        @font-face { src: url("/a-#{'#{$w}'}.woff2"); }
      }
      @each $w in (700) {
        @font-face { src: url("/b-#{'#{$w}'}.woff2"); }
      }
    SCSS
    blocks = L.each_blocks(body)
    offset = body.index("/b-")

    assert_equal ["/b-700.woff2"], L.expand('/b-#{$w}.woff2', offset, blocks)
  end

  # A query string and a fragment are cache-busting and glyph-selecting sugar, not
  # part of the filename: lightGallery ships `lg.woff2?io9a6k` and `lg.svg?io9a6k#lg`.
  def test_query_and_fragment_are_not_part_of_the_filename
    root = File.join(L::RAILS_ROOT, "shared/public")

    assert L.satisfied?("/fonts/lg.woff2?io9a6k", [root])
    assert L.satisfied?("fonts/lg.woff2?io9a6k#lg", [root])
  end

  def test_remote_and_inline_references_are_not_assets
    sheet = File.join(L::RAILS_ROOT, "brgen/app/assets/stylesheets/_fonts_brand.scss")
    refs = L.refs_in(sheet)

    refute_empty refs
    refute refs.any? { |r| r.start_with?("data:", "http", "//") },
           "a CDN fallback and a data: URI are not files this tree owns"
  end

  # An empty scan reads as a clean tree, which is the failure mode every gate here
  # exists to catch.
  def test_it_reads_something
    assert_operator L.sheets.size, :>, 100, "the stylesheet glob stopped matching"
    assert_operator L.refs_in(File.join(L::RAILS_ROOT, "shared/app/assets/stylesheets/_fonts.scss")).size, :>=, 2
  end
end
