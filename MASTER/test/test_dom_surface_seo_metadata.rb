# frozen_string_literal: true

require "minitest/autorun"
require_relative "../checks/support/dom_surface_schema"

class DomSurfaceSeoMetadataTest < Minitest::Test
  SCHEMA_ID = "brgen_home"
  COMPLETE_PAGE = <<~HTML
    <!doctype html>
    <html>
      <head>
        <title>Brgen — Bergen</title>
        <meta name="description" content="Bergen, right now: people, places and local life.">
        <link rel="canonical" href="https://brgen.no/">
        <meta property="og:title" content="Brgen — Bergen">
        <meta property="og:description" content="Bergen, right now: people, places and local life.">
        <meta property="og:url" content="https://brgen.no/">
      </head>
      <body>
        <a class="skip-link" href="#main-content">Skip to main</a>
        <main id="main-content">
          <h1>Home</h1>
          <p>Bergen local feed</p>
          <a href="/nearby/room">Nearby room</a>
        </main>
      </body>
    </html>
  HTML

  def setup
    @schema = Deploy::DomSurfaceSchema.new
  end

  def test_complete_page_passes_surface_and_metadata_contract
    assert_empty @schema.check(COMPLETE_PAGE, SCHEMA_ID)
  end

  def test_valid_metadata_values_may_contain_apostrophes
    html = COMPLETE_PAGE
      .gsub('content="Bergen, right now: people, places and local life."', 'content="Here\\'s what is happening in Bergen."')
      .sub('content="Brgen — Bergen"', 'content="Brgen\\'s Bergen"')

    assert_empty @schema.check(html, SCHEMA_ID)
  end

  def test_missing_meta_description_is_named
    html = COMPLETE_PAGE.sub(/\s*<meta name="description"[^>]*>\n/, "\n")
    messages = @schema.check(html, SCHEMA_ID).map(&:message)
    assert messages.any? { |message| message.include?("meta_description") }, messages.join("\n")
  end

  def test_duplicate_canonical_is_rejected
    canonical = '<link rel="canonical" href="https://brgen.no/">'
    html = COMPLETE_PAGE.sub("</head>", "  #{canonical}\n</head>")
    messages = @schema.check(html, SCHEMA_ID).map(&:message)
    assert messages.any? { |message| message.include?("canonical_url") }, messages.join("\n")
  end

  def test_relative_canonical_is_rejected
    html = COMPLETE_PAGE.sub("href=" + '"https://brgen.no/"', 'href="/"' )
    messages = @schema.check(html, SCHEMA_ID).map(&:message)
    assert messages.any? { |message| message.include?("canonical_url") }, messages.join("\n")
  end
end
