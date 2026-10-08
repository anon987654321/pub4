# frozen_string_literal: true

require "minitest/autorun"
require "time"
require_relative "../../app/services/shared/sitemap_builder"

# Guards the require: without it Builder resolved under Shared and every app's /sitemap.xml answered 500.
class SharedSitemapBuilderTest < Minitest::Test
  def test_renders_a_urlset_for_every_entry
    xml = Shared::SitemapBuilder.render([
      Shared::SitemapBuilder::Entry.new(loc: "https://bsdports.org/ports/git"),
      Shared::SitemapBuilder::Entry.new(loc: "https://bsdports.org/", changefreq: "daily", priority: "1.0"),
    ])

    assert_includes xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    assert_includes xml, "xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\""
    assert_includes xml, "<loc>https://bsdports.org/ports/git</loc>"
    assert_includes xml, "<changefreq>daily</changefreq>"
    assert_equal 2, xml.scan("<url>").size
  end

  def test_emits_lastmod_only_when_given
    stamp = Time.utc(2026, 8, 2, 12, 0, 0)
    dated = Shared::SitemapBuilder::Entry.new(loc: "https://brgen.no/", lastmod: stamp)
    with_stamp = Shared::SitemapBuilder.render([ dated ])
    without = Shared::SitemapBuilder.render([ Shared::SitemapBuilder::Entry.new(loc: "https://brgen.no/") ])

    assert_includes with_stamp, "<lastmod>#{stamp.iso8601}</lastmod>"
    refute_includes without, "<lastmod>"
  end

  def test_escapes_urls_that_would_break_the_document
    xml = Shared::SitemapBuilder.render([ Shared::SitemapBuilder::Entry.new(loc: "https://brgen.no/search?q=a&b=1") ])

    assert_includes xml, "q=a&amp;b=1"
  end
end
