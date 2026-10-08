# frozen_string_literal: true

require "minitest/autorun"

class CookieConsentContractTest < Minitest::Test
  ROOT = ENV.fetch("ONBOARDING_TEST_ROOT", File.expand_path("..", __dir__))
  BANNER = File.join(ROOT, "__shared/app/views/shared/_cookie_banner.html.erb")
  COOKIE = File.join(ROOT, "shared/frontend/cookie_consent.js")
  CONTROLLER = File.join(ROOT, "shared/frontend/cookie_consent_controller.js")
  HELPER = File.join(ROOT, "__shared/app/helpers/shared/consent_helper.rb")
  HOTWIRE = File.join(ROOT, "shared/frontend/hotwire.js")
  LINK_CONVERTER = File.join(ROOT, "__shared/app/views/shared/_link_converter.html.erb")
  BRGEN_LAYOUT = File.join(ROOT, "brgen/app/views/layouts/application.html.erb")
  AMBER_LAYOUT = File.join(ROOT, "amber/app/views/layouts/application.html.erb")

  def test_accept_and_reject_are_on_the_first_layer
    body = File.read(BANNER)
    assert_includes body, %(data-action="cookie-consent#reject")
    assert_includes body, %(data-action="cookie-consent#accept")
    refute_match(/input[^>]+checked/, body)
  end

  def test_consent_is_purpose_scoped_and_long_lived
    body = File.read(COOKIE)
    assert_includes body, %(COOKIE_NAME = "pub4_consent")
    assert_includes body, %(PURPOSES = [ "analytics", "advertising" ])
    assert_includes body, "Max-Age=31536000"
    assert_includes body, "SameSite=Lax"
  end

  def test_optional_technology_waits_for_consent
    assert_includes File.read(HOTWIRE), %(allows("analytics"))
    assert_includes File.read(LINK_CONVERTER), %(controller: "link-converter")
    assert_includes File.read(CONTROLLER), %(saveConsent(selected))
  end

  def test_both_apps_mount_the_banner_controller
    assert_match(/data-controller="[^"]*cookie-consent/, File.read(BRGEN_LAYOUT))
    assert_match(/data-controller="[^"]*cookie-consent/, File.read(AMBER_LAYOUT))
    assert_includes File.read(BANNER), %(data-cookie-consent-target="banner")
  end

  def test_server_helper_matches_browser_signal
    body = File.read(HELPER)
    assert_includes body, %(CONSENT_COOKIE = "pub4_consent")
    assert_includes body, %(CONSENT_VERSION = "v1")
    assert_includes body, "analytics"
    assert_includes body, "advertising"
  end
end
