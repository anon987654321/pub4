# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_guest_root_shows_animated_amber_logo
    get root_url
    assert_response :success
    assert_includes response.body, "amber-guest-hero"
    assert_includes response.body, "amber-logo-banner"
    assert_includes response.body, "animated-gradient"
    # Through the key, so it follows the locale amber resolves to (nb by
    # default) rather than pinning the English copy — same fix as b369c6213
    # made for brgen's home and signup pages.
    assert_includes response.body, I18n.t("home.guest_title")
    assert_includes response.body, "amber-wardrobe-showcase"
    assert_includes response.body, 'data-controller="carousel"'
    assert_includes response.body, "Headwear"
    assert_includes response.body, "Shoes"
    assert_includes response.body, "amber-compose-box"
    assert_includes response.body, I18n.t("empty.guest_post")
    assert_not_includes response.body, 'class="master-embed-frame"'
  end

  def test_guest_root_can_open_master_embed
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
  end
end
