# frozen_string_literal: true

require "minitest/autorun"

# allow_browser answers an old browser by rendering public/406-unsupported-browser.html.
# With the file missing, that answer was itself an ArgumentError, so the visitor got a 500.
class PublicErrorPagesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MASTER_WEB_PAGES = %w[400 404 422 500].freeze
  MASTER_WEB_FONT = 'font-family: "Helvetica Neue Pro", "Helvetica Neue", Arial, sans-serif;'

  %w[brgen amber bsdports].each do |app|
    define_method("test_#{app}_has_every_page_rails_renders_for_a_status") do
      %w[404 406-unsupported-browser 422 500].each do |name|
        assert File.file?(File.join(ROOT, app, "public", "#{name}.html")), "#{app}/public/#{name}.html is missing"
      end
    end
  end

  def test_master_web_error_pages_share_the_application_typographic_stack
    MASTER_WEB_PAGES.each do |status|
      path = File.join(ROOT, "master_web", "public", "#{status}.html")
      assert File.file?(path), "master_web/public/#{status}.html is missing"
      source = File.read(path)

      assert_includes source, 'lang="nb"', "#{status}: error language must remain Norwegian"
      assert_includes source, MASTER_WEB_FONT, "#{status}: error page drifted from the app typeface"
      assert_includes source, "line-height: 1.4;", "#{status}: error-page reading rhythm drifted"
      assert_includes source, "viewport-fit=cover", "#{status}: safe-area viewport was lost"
    end
  end

  def test_shared_503_fallback_uses_brand_typography_and_safe_area
    source = File.read(File.join(ROOT, "__shared", "public", "503.html"))

    assert_includes source, MASTER_WEB_FONT
    assert_includes source, "line-height: 1.5;"
    assert_includes source, "0.8rem/1.25 ui-monospace"
    assert_includes source, "min-height: 100dvh"
    assert_includes source, "env(safe-area-inset-top"
    assert_includes source, "env(safe-area-inset-bottom"
    refute_match(/(?:box-shadow|text-shadow|backdrop-filter)\s*:\s*(?!none\b)/, source)
  end
end
