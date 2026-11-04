# frozen_string_literal: true

require "test_helper"

# Twenty-one amber views gave their in-page <header> role="banner", so a
# page had a second banner landmark beside the masthead and screen-reader
# landmark lists named the page header as the site banner.
class LandmarkBannerTest < ActionDispatch::IntegrationTest
  test "page headers inside main are not banners" do
    email = "lb-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    item = Item.strict_loading(false).create!(user:, title: "Frakk", category: "outerwear", times_worn: 0,
                                              price_cents: 0, lifecycle_state: "declutter_box")
    outfit = Outfit.strict_loading(false).create!(user:, name: "Fredag")

    paths = [ items_path, new_item_path, item_path(item), outfits_path, new_outfit_path, outfit_path(outfit),
              declutter_index_path, review_declutter_path(item), analytics_wardrobe_items_path,
              timeline_wardrobe_items_path, messages_path, connections_path, live_streams_path,
              user_path(user) ]
    paths.each do |path|
      get path
      assert_response :success, path
      assert_select "main [role=banner]", 0, path
    end
  end
end
