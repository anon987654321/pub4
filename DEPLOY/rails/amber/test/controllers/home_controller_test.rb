# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_guest_root_shows_animated_amber_logo
    get root_url
    assert_response :success
    assert_includes response.body, "amber-guest-hero"
    assert_includes response.body, "amber-logo-gradient"
    assert_includes response.body, "amber-swoosh-line"
    assert_includes response.body, "Amber turns your wardrobe into a working system."
    assert_not_includes response.body, 'class="master-embed-frame"'
  end

  def test_guest_root_can_open_master_embed
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
  end
end