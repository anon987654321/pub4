# frozen_string_literal: true

require "test_helper"

class RecentFeaturesIntegrationTest < ActionDispatch::IntegrationTest
  def sign_in_amber(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  test "creator profile is private until published" do
    user = User.strict_loading(false).create!(email_address: "creator@example.com", password: "password")
    profile = user.create_creator_profile!(
      handle: "creator_test",
      display_name: "Creator Test",
      public: false
    )

    get creator_profile_path(profile.handle)
    assert_redirected_to root_path
  end

  test "signed-in user can create and showcase creator profile" do
    user = User.strict_loading(false).create!(email_address: "showcase@example.com", password: "password")
    item = user.items.create!(title: "Blazer", category: "outerwear")
    sign_in_amber(user)

    post my_creator_profile_path, params: {
      creator_profile: {
        handle: "showcase_creator",
        display_name: "Showcase Creator",
        bio: "Capsule wardrobe",
        public: true
      }
    }
    assert_redirected_to creator_profile_path("showcase_creator")

    profile.reload
    assert profile.public?

    post creator_profile_wardrobe_items_path(handle: profile.handle), params: { item_id: item.id, caption: "Daily blazer" }
    assert_redirected_to edit_my_creator_profile_path
    assert profile.creator_wardrobe_items.exists?(item: item)

    get creator_profile_path(profile.handle)
    assert_response :success
    assert_includes response.body, "Showcase"
    assert_includes response.body, "Daily blazer"
  end

  test "wardrobe item join is unique per user and item" do
    user = User.strict_loading(false).create!(email_address: "wardrobe@example.com", password: "password")
    item = user.items.create!(title: "Shirt", category: "tops")
    sign_in_amber(user)

    WardrobeItem.create!(user: user, item: item, condition: "good")
    duplicate = WardrobeItem.new(user: user, item: item, condition: "worn")
    assert_not duplicate.valid?
  end
end