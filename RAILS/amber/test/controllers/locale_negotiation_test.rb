# frozen_string_literal: true

require "test_helper"

# Amber shipped `available_locales = %i[nb en]` and no way to reach `en`.
class LocaleNegotiationTest < ActionDispatch::IntegrationTest
  test "a visitor with no preference gets the default" do
    get root_url

    assert_response :success
    assert_select "html[lang=?]", "nb"
  end

  test "Accept-Language is honoured" do
    get root_url, headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }

    assert_response :success
    assert_select "html[lang=?]", "en"
    assert_includes response.body, I18n.t("home.guest_title", locale: :en)
  end

  test "the highest-quality supported language wins, not the first listed" do
    get root_url, headers: { "HTTP_ACCEPT_LANGUAGE" => "de;q=0.9,en;q=0.8,nb;q=0.3" }

    assert_response :success
    # German is not available, so English outranks Norwegian on quality.
    assert_select "html[lang=?]", "en"
  end

  test "an unsupported Accept-Language falls back to the default" do
    get root_url, headers: { "HTTP_ACCEPT_LANGUAGE" => "de-DE,de;q=0.9" }

    assert_response :success
    assert_select "html[lang=?]", "nb"
  end

  test "an explicit switch outranks the browser and sticks for later requests" do
    get root_url(locale: "en"), headers: { "HTTP_ACCEPT_LANGUAGE" => "nb" }
    assert_select "html[lang=?]", "en"

    # No ?locale= and a Norwegian browser: the session still wins.
    get root_url, headers: { "HTTP_ACCEPT_LANGUAGE" => "nb" }
    assert_select "html[lang=?]", "en"
  end

  test "an unknown locale parameter is ignored rather than served" do
    get root_url(locale: "xx")

    assert_response :success
    assert_select "html[lang=?]", "nb"
  end

  test "the footer offers every available locale and marks the current one" do
    get root_url

    assert_response :success
    assert_select ".amber-footer-locales a", count: I18n.available_locales.size
    assert_select ".amber-footer-locales a.is-current[aria-current=true]", count: 1
    assert_select ".amber-footer-locales a.is-current", text: I18n.t("footer.locales.nb")
  end

  test "switching keeps you on the page you were reading" do
    get items_url(lifecycle: "repair"), headers: { "HTTP_ACCEPT_LANGUAGE" => "nb" }
    # Signed out, items redirects — follow to wherever it lands and check the
    # switcher points back at that same path.
    follow_redirect! while response.redirect?

    href = css_select(".amber-footer-locales a").first["href"]
    assert href.start_with?(path), "switcher left the current page: #{href}"
    assert_includes href, "locale="
  end
end
