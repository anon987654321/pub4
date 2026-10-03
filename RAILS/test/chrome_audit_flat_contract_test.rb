# frozen_string_literal: true

require "minitest/autorun"

class ChromeAuditFlatContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_shared_form_controls_are_borderless_but_keep_focus
    source = read("shared/app/assets/stylesheets/_components.scss")
    assert_includes source, "border: 0;"
    assert_includes source, "outline: var(--focus-ring);"
    assert_includes source, "outline: 2px solid var(--danger);"
    assert_includes source, "color-mix(in srgb, var(--danger) 8%, var(--surface))"
  end

  def test_auth_and_promo_surfaces_do_not_reintroduce_container_borders
    auth = read("shared/app/assets/stylesheets/_auth_form.scss")
    promo = read("brgen/app/assets/stylesheets/vertical_promo.css")
    assert_includes auth, ".oauth-button {"
    assert_includes auth, "border: 0;"
    assert_includes promo, ".brgen-vertical-promo {"
    assert_includes promo, "background: var(--bg);"
    assert_includes promo, ".brgen-vertical-promo__disc {"
    assert_includes promo, "border: 0;"
  end

  def test_dialog_sheet_consent_and_affiliate_chrome_is_flat
    modal = read("shared/app/assets/stylesheets/_modal.scss")
    cookie = read("shared/app/assets/stylesheets/_cookie_banner.scss")
    affiliate = read("shared/app/assets/stylesheets/_affiliate_feed_unit.scss")
    commerce = read("brgen/app/assets/stylesheets/_commerce_polish.scss")
    offline = read("shared/app/assets/stylesheets/_offline_page.scss")
    widgets = read("shared/app/assets/stylesheets/_shell_widgets.scss")
    newsletter = read("shared/app/assets/stylesheets/_newsletter_capture.scss")

    [modal, cookie, affiliate, commerce, offline, widgets, newsletter].each do |source|
      refute_match(/box-shadow:\s*(?!none)/, source)
    end

    assert_includes modal, ".dialog {"
    assert_includes cookie, ".cookie-banner {"
    assert_includes affiliate, ".affiliate_feed_unit {"
    assert_includes commerce, ".store-buybox {"
    assert_includes offline, ".offline-page-retry {"
    assert_includes widgets, ".sidebar-card {"
    assert_includes newsletter, ".newsletter-capture {"
  end
end
