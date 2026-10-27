# frozen_string_literal: true

require "minitest/autorun"

class ChromeAuditFlatContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_shared_form_controls_are_borderless_but_keep_focus
    source = %w[components/_forms.scss components/_overlays.scss components/_fields.scss]
             .map { |path| read("__shared/app/assets/stylesheets/#{path}") }.join("\n")
    assert_includes source, "border: 0;"
    assert_includes source, "outline: var(--focus-ring);"
    assert_includes source, "outline: 2px solid var(--danger);"
    assert_includes source, "color-mix(in srgb, var(--danger) 8%, var(--surface))"
  end

  def test_auth_and_promo_surfaces_do_not_reintroduce_container_borders
    auth = read("__shared/app/assets/stylesheets/_auth_form.scss")
    promo = read("brgen/app/assets/stylesheets/_vertical_promo.scss")
    app = read("brgen/app/assets/stylesheets/application.scss")
    assert_includes auth, ".oauth-button {"
    assert_includes auth, "border: 0;"
    assert_includes app, '@use "vertical_promo";'
    assert_includes promo, ".brgen-vertical-promo {"
    assert_includes promo, "background: var(--bg);"
    assert_includes promo, ".promo-disc {"
    assert_includes promo, "border: 0;"
  end

  def test_vertical_promo_action_does_not_duplicate_link_affordance_with_an_arrow
    source = read("brgen/app/views/home/_vertical_promo_unit.html.erb")
    assert_includes source, '<%= t("promo.#{slug}.action") %>'
    refute_includes source, "→"
  end

  def test_brgen_uses_the_shared_canonical_reduced_motion_reset
    source = read("brgen/app/assets/stylesheets/application.scss")
    stack = read("__shared/app/assets/stylesheets/_stack_brgen.scss")
    animations = read("__shared/app/assets/stylesheets/_animations.scss")

    assert_includes source, '@use "stack_brgen" as *;'
    assert_includes stack, '@forward "animations";'
    assert_match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\*::before,[\s\S]*animation: none !important;[\s\S]*transition: none !important;[\s\S]*scroll-behavior: auto !important;/m, animations)
    refute_includes source, "animation: none !important;"
    refute_includes source, "Last in the cascade: reduced motion must survive"
  end

  def test_consent_banner_is_mobile_first_and_restores_wide_layout
    source = read("__shared/app/assets/stylesheets/_cookie_banner.scss")
    mobile = source.split("@media (min-width: 768px)", 2).first
    wide = source.split("@media (min-width: 768px)", 2).last

    refute_match(/@media\s*\(\s*max-width\b/, source,
                 "the shared consent banner must not use a max-width override")
    assert_match(/\.cookie-banner\s*\{[^}]*grid-template-columns:\s*1fr;[^}]*max-height:\s*min\(90dvh,\s*42rem\);[^}]*overflow-y:\s*auto;/m, mobile)
    assert_match(/\.cookie-banner-actions\s*\{[^}]*justify-content:\s*stretch;/m, mobile)
    assert_match(/\.cookie-banner-button\s*\{[^}]*flex:\s*1 1 9rem;/m, mobile)
    assert_match(/\.cookie-consent-preferences\s*\{[^}]*grid-template-columns:\s*1fr;/m, mobile)
    assert_match(/\.cookie-banner\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) auto;[^}]*max-height:\s*none;[^}]*overflow-y:\s*visible;/m, wide)
    assert_match(/\.cookie-banner-button\s*\{[^}]*flex:\s*0 1 auto;/m, wide)
    assert_match(/\.cookie-consent-preferences\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) minmax\(18rem, 1fr\);/m, wide)
  end

  def test_dialog_sheet_consent_and_affiliate_chrome_is_flat
    modal = read("__shared/app/assets/stylesheets/_modal.scss")
    cookie = read("__shared/app/assets/stylesheets/_cookie_banner.scss")
    affiliate = read("__shared/app/assets/stylesheets/_affiliate_feed_unit.scss")
    commerce = read("brgen/app/assets/stylesheets/_commerce_polish.scss")
    offline = read("__shared/app/assets/stylesheets/_offline_page.scss")
    widgets = read("__shared/app/assets/stylesheets/_shell_widgets.scss")
    newsletter = read("__shared/app/assets/stylesheets/_newsletter_capture.scss")

    [modal, cookie, affiliate, commerce, offline, widgets, newsletter].each do |source|
      refute_match(/box-shadow:(?!\s*none\b)/, source)
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
