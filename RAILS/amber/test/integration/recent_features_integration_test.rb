# frozen_string_literal: true

require "test_helper"

class RecentFeaturesIntegrationTest < ActionDispatch::IntegrationTest
  def sign_in_amber(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  test "departing user profiles are not public" do
    user = User.strict_loading(false).create!(email_address: "departing-user@example.com", password: "password")
    user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get user_path(user)

    assert_response :not_found
  end

  test "creator profile is private until published" do
    user = User.strict_loading(false).create!(email_address: "creator@example.com", password: "password")
    profile = user.create_creator_profile!(
      handle: "creator_test",
      display_name: "Creator Test",
      public: false
    )

    # The lookup is scoped to publicly_visible (de4c4251e), so a private profile
    # is not found at all rather than redirected: its existence is not disclosed.
    get creator_profile_path(profile.handle)
    assert_response :not_found
  end

  test "departing creator profiles are no longer public" do
    user = User.strict_loading(false).create!(email_address: "departing-creator@example.com", password: "password")
    profile = user.create_creator_profile!(
      handle: "departing_creator",
      display_name: "Departing Creator",
      public: true
    )
    user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get creator_profile_path(profile.handle)

    assert_response :not_found
  end

  test "departing authors lose attribution without losing retained post content" do
    user = User.strict_loading(false).create!(email_address: "departing-poster@example.com", password: "password")
    post = user.posts.create!(body: "A retained post", anonymous: false)
    user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    assert_equal "anon", post.reload.author_name
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

    profile = CreatorProfile.find_by!(user: user)
    assert profile.public?

    post creator_profile_wardrobe_items_path(handle: profile.handle), params: { item_id: item.id, caption: "Daily blazer" }
    assert_redirected_to edit_my_creator_profile_path
    assert profile.creator_wardrobe_items.exists?(item: item)

    get creator_profile_path(profile.handle)
    assert_response :success
    assert_includes response.body, "Showcase"
    assert_includes response.body, "Daily blazer"
  end

  test "departing users cannot receive new social relationships" do
    actor = User.strict_loading(false).create!(email_address: "social-actor@example.com", password: "password")
    target = User.strict_loading(false).create!(email_address: "social-target@example.com", password: "password")
    target.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)
    sign_in_amber(actor)

    assert_no_difference -> { Follow.count } do
      post follow_user_path(target)
    end
    assert_response :not_found

    assert_no_difference -> { Connection.count } do
      post connections_path, params: { user_id: target.id }
    end
    assert_response :not_found
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
