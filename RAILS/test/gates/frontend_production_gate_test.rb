# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/frontend_production"

# The application shell, read as text.
#
# Six properties of a layout that a browser never complains about and a person
# only notices once: no `lang` on `<html>`, a viewport without
# `viewport-fit=cover` so the page ends under the notch, no charset, no CSP
# meta, no way to skip past the chrome to the content, and a raw `<%= %>` that
# interpolates without sanitizing.
#
# check_layout takes the path and check_views takes the app directory, so both
# run over a fixture with no constant rewriting. Each defect below is planted
# into an otherwise sound shell, so a failure names the one thing that changed.
class FrontendProductionGateTest < Minitest::Test
  include GateFixture

  SOUND_LAYOUT = <<~ERB
    <!DOCTYPE html>
    <html lang="nb">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <%= csp_meta_tag %>
      </head>
      <body>
        <a href="#main-content">Hopp til hovedinnhold</a>
        <main id="main-content"><%= yield %></main>
      </body>
    </html>
  ERB

  def issues_for(body)
    Dir.mktmpdir do |dir|
      path = plant(dir, "app/views/layouts/application.html.erb", body)
      Deploy::FrontendProductionGate.new.send(:check_layout, path)
    end
  end

  def test_the_sound_shell_raises_nothing
    assert_empty issues_for(SOUND_LAYOUT)
  end

  def test_a_missing_lang_attribute_is_named
    assert_includes issues_for(SOUND_LAYOUT.sub('<html lang="nb">', "<html>")), "missing lang on <html>"
  end

  # The notch. A viewport meta without viewport-fit=cover is the defect, not the
  # absence of a viewport meta, so the gate has to tell those two apart.
  def test_a_viewport_without_cover_is_named
    body = SOUND_LAYOUT.sub(", viewport-fit=cover", "")

    assert_includes issues_for(body), "missing viewport-fit=cover"
    refute_includes issues_for(body), "missing viewport meta"
  end

  def test_a_missing_viewport_meta_is_named
    assert_includes issues_for(SOUND_LAYOUT.sub(/^ *<meta name="viewport".*\n/, "")), "missing viewport meta"
  end

  def test_a_missing_charset_is_named
    assert_includes issues_for(SOUND_LAYOUT.sub(/^ *<meta charset.*\n/, "")), "missing charset meta"
  end

  def test_a_missing_csp_meta_is_named
    assert_includes issues_for(SOUND_LAYOUT.sub(/^ *<%= csp_meta_tag %>\n/, "")), "missing CSP meta"
  end

  def test_a_shell_with_no_route_past_the_chrome_is_named
    body = SOUND_LAYOUT.gsub("main-content", "content").sub(/^ *<a href.*\n/, "")

    assert_includes issues_for(body), "missing skip link or #main-content"
  end

  def test_an_unsanitised_interpolation_is_named
    body = SOUND_LAYOUT.sub("<%= yield %>", "<%= @post.body.html_safe %>")

    assert_includes issues_for(body), "unsafe raw <%= without sanitize"
  end

  # Sanitized is the same construct and must not be reported, or the rule gets
  # switched off rather than obeyed.
  def test_a_sanitised_interpolation_is_not_named
    body = SOUND_LAYOUT.sub("<%= yield %>", "<%= sanitize(@post.body).html_safe %>")

    refute_includes issues_for(body), "unsafe raw <%= without sanitize"
  end

  # A link whose href is "#" looks like an action and does nothing without
  # JavaScript, so it is a dead end in the layout every page wears.
  def test_a_hash_href_in_a_layout_is_reported
    Dir.mktmpdir do |dir|
      plant(dir, "app/views/layouts/application.html.erb", SOUND_LAYOUT)
      plant(dir, "app/views/layouts/_nav.html.erb", %(<a href="#">Meny</a>\n))
      issues = Deploy::FrontendProductionGate.new.send(:check_views, dir)

      assert_equal 1, issues.size
      assert_match(/_nav\.html\.erb: <a href='#'> action link/, issues.first)
    end
  end

  def test_layouts_without_a_hash_href_are_clean
    Dir.mktmpdir do |dir|
      plant(dir, "app/views/layouts/application.html.erb", SOUND_LAYOUT)
      plant(dir, "app/views/layouts/_nav.html.erb", %(<a href="/meny">Meny</a>\n))

      assert_empty Deploy::FrontendProductionGate.new.send(:check_views, dir)
    end
  end
end
