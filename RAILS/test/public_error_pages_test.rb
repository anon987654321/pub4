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
        path = File.join(ROOT, app, "public", "#{name}.html")
        assert File.file?(path), "#{app}/public/#{name}.html is missing"
        source = File.read(path)

        assert_includes source, 'lang="nb"', "#{app}/#{name}: public copy must declare Norwegian"
        assert_match(/name="viewport" content="[^"]*viewport-fit=cover/, source,
                     "#{app}/#{name}: safe-area viewport was lost")
        assert_includes source, %(<link rel="stylesheet" href="/styles/errors.css">),
                        "#{app}/#{name}: error pages must use the shared typographic treatment"
      end
    end
  end

  def test_public_error_pages_do_not_depend_on_javascript_urls
    paths = Dir.glob(File.join(ROOT, "{__shared,brgen,amber,bsdports,master}", "public", "{400,404,406-unsupported-browser,422,500,503}.html"))

    refute_empty paths, "no public error pages found — the inventory stopped matching"
    paths.each do |path|
      refute_match(/href\s*=\s*["']\s*javascript:/i, File.read(path),
                      "#{path.delete_prefix("#{ROOT}/")}: use a real destination, not a javascript: URL")
    end
  end

  def test_422_copy_matches_the_safe_home_destination
    { "brgen" => "Hjem", "amber" => "Hjem", "bsdports" => "Porter" }.each do |app, home|
      source = File.read(File.join(ROOT, app, "public", "422.html"))

      assert_includes source, %(href="/">#{home}</a>)
      assert_includes source, "Gå til forsiden"
      assert_includes source, "Return to the home page"
      refute_match(/Gå tilbake|Go back/i, source)
    end
  end

  def test_master_web_error_pages_share_the_application_typographic_stack
    MASTER_WEB_PAGES.each do |status|
      path = File.join(ROOT, "..", "MASTER", "web", "public", "#{status}.html")
      assert File.file?(path), "MASTER/web/public/#{status}.html is missing"
      source = File.read(path)

      assert_includes source, 'lang="nb"', "#{status}: error language must remain Norwegian"
      assert_includes source, MASTER_WEB_FONT, "#{status}: error page drifted from the app typeface"
      assert_includes source, "line-height: 1.4;", "#{status}: error-page reading rhythm drifted"
      assert_includes source, "viewport-fit=cover", "#{status}: safe-area viewport was lost"
    end
  end

  def test_master_unsupported_browser_page_keeps_the_terminal_dialect
    source = File.read(File.join(ROOT, "..", "MASTER", "web", "public", "406-unsupported-browser.html"))

    assert_includes source, 'lang="nb"'
    assert_match(/name="viewport" content="[^"]*viewport-fit=cover/, source)
    assert_includes source, 'font: 400 15px/1.5 ui-monospace, "JetBrains Mono", Menlo, monospace;'
    assert_includes source, "min-height: 100dvh;"
    assert_includes source, "min-height: 44px;"
    assert_includes source, "border-radius: 0;"
    refute_match(/(?:box-shadow|text-shadow|backdrop-filter)\s*:\s*(?!none\b)/, source)
  end

  def test_shared_error_stylesheet_keeps_type_rhythm_tokens_and_flat_surfaces
    source = File.read(File.join(ROOT, "__shared", "public", "styles", "errors.css"))

    assert_includes source, "font-family: var(--font);"
    assert_includes source, "font-size: clamp(0.9375rem, 2.5vw, 1.25rem);"
    assert_includes source, "line-height: 1.5;"
    assert_includes source, "min-height: 100dvh;"
    # The control height, radius and focus ring are the generated tokens, not
    # literals typed beside them (shared-049).
    assert_includes source, %(@import url("/styles/tokens.css");)
    assert_includes source, "min-height: var(--tap-min);"
    assert_includes source, "border-radius: var(--radius-extra-small);"
    refute_match(/min-height: 44px|border-radius: 4px/, source)
    tokens = File.read(File.join(ROOT, "__shared", "public", "styles", "tokens.css"))
    assert_includes tokens, "--tap-min: 44px;"
    assert_includes tokens, "--radius-extra-small: 4px;"
    assert_includes tokens, "--focus-ring: 2px solid var(--accent, currentColor);"
    %w[top right bottom left].each do |edge|
      assert_includes source, "env(safe-area-inset-#{edge}, 0px)",
                      "shared error-page padding must respect the #{edge} safe area"
    end
    assert_includes source, "background: var(--bg);"
    assert_includes source, "color: var(--text);"
    assert_includes source, ":focus-visible"
    assert_includes source, "outline: var(--focus-ring);"
    assert_includes source, "@media (forced-colors: active)"
    assert_includes source, "outline-color: Highlight;"
    refute_match(/(?:box-shadow|text-shadow|backdrop-filter)\s*:\s*(?!none\b)/, source)
  end

  # The 503 page carried its own inline palette and type; it now reads the one
  # errors.css the 400 page and every app's error pages read, so its type,
  # safe-area padding and focus ring come from the stylesheet tested above.
  def test_shared_error_pages_link_the_shared_stylesheet_and_carry_no_palette_of_their_own
    %w[400 503].each do |status|
      source = File.read(File.join(ROOT, "__shared", "public", "#{status}.html"))

      assert_includes source, %(<link rel="stylesheet" href="/styles/errors.css">), "#{status}: must read errors.css"
      refute_match(/<style\b/, source, "#{status}: an inline palette drifts from errors.css")
      assert_match(/name="viewport" content="[^"]*viewport-fit=cover/, source)
      assert_includes source, %(<p class="kicker">#{status}</p>)
    end
  end
end
