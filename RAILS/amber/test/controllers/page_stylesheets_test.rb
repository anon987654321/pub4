# frozen_string_literal: true

require "test_helper"

# The layout linked /swiper-bundle.min.css, which no amber view uses, and
# /lightgallery.css, which only the item page's lightbox uses, as
# render-blocking stylesheets on every page.
class PageStylesheetsTest < ActionDispatch::IntegrationTest
  setup do
    email = "css-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: @user.email_address, password: "password" }
  end

  test "an ordinary page loads neither stylesheet" do
    get posts_path
    assert_response :success
    assert_select "head link[href='/swiper-bundle.min.css']", 0
    assert_select "head link[href='/lightgallery.css']", 0
  end

  test "the item page loads the lightbox stylesheet once" do
    item = Item.strict_loading(false).create!(user: @user, title: "Frakk", category: "outerwear",
                                              times_worn: 0, price_cents: 0)

    get item_path(item)
    assert_response :success
    assert_select "head link[rel=stylesheet][href='/lightgallery.css']", 1
  end
end
