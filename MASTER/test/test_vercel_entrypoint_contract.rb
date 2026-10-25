# frozen_string_literal: true

require "json"
require "minitest/autorun"

class TestVercelEntrypointContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__).freeze

  def test_vercel_serves_an_explicit_static_output_directory
    config = JSON.parse(File.read(File.join(ROOT, "vercel.json"), encoding: "UTF-8"))

    assert_nil config.fetch("framework")
    assert_equal "public", config.fetch("outputDirectory")
    assert File.file?(File.join(ROOT, config.fetch("outputDirectory"), "index.html")),
           "configured Vercel output directory must contain its index"
  end

  def test_static_response_has_a_restrictive_security_header_contract
    config = JSON.parse(File.read(File.join(ROOT, "vercel.json"), encoding: "UTF-8"))
    route = config.fetch("headers").find { |entry| entry.fetch("source") == "/(.*)" }
    refute_nil route, "static entrypoint must have a global response-header rule"
    headers = route.fetch("headers").to_h { |entry| [entry.fetch("key"), entry.fetch("value")] }

    csp = headers.fetch("Content-Security-Policy")
    assert_includes csp, "default-src 'none'"
    assert_includes csp, "style-src 'self'"
    assert_includes csp, "frame-ancestors 'none'"
    assert_equal "DENY", headers.fetch("X-Frame-Options")
    assert_equal "nosniff", headers.fetch("X-Content-Type-Options")
    assert_equal "strict-origin-when-cross-origin", headers.fetch("Referrer-Policy")
    assert_equal "camera=(), geolocation=(), microphone=()", headers.fetch("Permissions-Policy")
  end

  def test_static_index_is_accessible_and_links_every_governed_tree
    html = File.read(File.join(ROOT, "public", "index.html"), encoding: "UTF-8")
    css_path = File.join(ROOT, "public", "styles.css")
    css = File.read(css_path, encoding: "UTF-8")

    assert_match(/\A<!doctype html>/i, html)
    assert_match(/<html lang="en">/, html)
    assert_includes html, 'name="viewport"'
    assert_includes html, 'href="#main"'
    assert_includes html, 'id="main"'
    assert_includes html, 'rel="stylesheet" href="/styles.css"'
    assert File.file?(css_path), "local stylesheet must exist"
    assert_equal 4, html.scan(/<h3\b/i).length, "every source tree needs a navigable heading"
    refute_match(/\sstyle=/i, html, "inline styles are disallowed by the Content Security Policy")
    assert_includes html, "does not boot MASTER"
    assert_includes html, "does not prove that the runtime or production host is healthy"
    refute_match(/<(?:script|iframe|object|embed)\b/i, html, "repository index must remain static")

    assert_includes css, ":focus-visible"
    assert_includes css, "prefers-color-scheme: dark"
    refute_match(/@import|url\(\s*https?:/i, css, "stylesheet must not pull remote assets")

    %w[MASTER RAILS OPENBSD STUDIO].each do |tree|
      assert_includes html, "https://github.com/anon987654321/pub4/tree/main/#{tree}"
    end
  end
  def test_text_pairs_meet_wcag_aa_contrast
    css = File.read(File.join(ROOT, "public", "styles.css"), encoding: "UTF-8")
    pages = css.scan(/--page:\s*(#[\da-f]{6})/i).flatten
    inks = css.scan(/--ink:\s*(#[\da-f]{6})/i).flatten
    muted = css.scan(/--muted:\s*(#[\da-f]{6})/i).flatten
    signal = css.match(/--signal:\s*(#[\da-f]{6})/i).captures.fetch(0)
    signal_ink = css.match(/--signal-ink:\s*(#[\da-f]{6})/i).captures.fetch(0)

    assert_equal 2, pages.size, "light and dark page colours must be explicit"
    assert_equal 2, inks.size, "light and dark text colours must be explicit"
    assert_equal 2, muted.size, "light and dark secondary text colours must be explicit"

    pairs = [
      [inks.fetch(0), pages.fetch(0), "light primary text"],
      [muted.fetch(0), pages.fetch(0), "light secondary text"],
      [inks.fetch(1), pages.fetch(1), "dark primary text"],
      [muted.fetch(1), pages.fetch(1), "dark secondary text"],
      [signal_ink, signal, "signal text"],
    ]

    pairs.each do |foreground, background, label|
      ratio = contrast_ratio(foreground, background)
      assert_operator ratio, :>=, 4.5, "#{label} contrast is #{ratio.round(2)}:1; need 4.5:1"
    end
  end

  private

  def contrast_ratio(foreground, background)
    relative_luminance = lambda do |hex|
      channels = hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) / 255.0 }
      linear = channels.map do |channel|
        channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
      end
      0.2126 * linear.fetch(0) + 0.7152 * linear.fetch(1) + 0.0722 * linear.fetch(2)
    end

    high, low = [relative_luminance.call(foreground), relative_luminance.call(background)].max,
                [relative_luminance.call(foreground), relative_luminance.call(background)].min
    (high + 0.05) / (low + 0.05)
  end

end
