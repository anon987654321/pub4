# frozen_string_literal: true

require "test_helper"

# The profile edit form says who someone is in their own words and picture:
# a short bio under the name, and an uploaded photo in place of the identicon.
class ProfileBioAndAvatarTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
    @me = User.create!(email_address: "bio-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                       username: "bio_#{SecureRandom.hex(3)}")
    post session_path, params: { email_address: @me.email_address, password: "password123" }
  end

  def photo = fixture_file_upload("tiny.png", "image/png")

  def photo_attached? = ActiveStorage::Attachment.exists?(record: @me, name: "avatar")

  test "the edit form offers a bio and a photo upload" do
    get edit_user_path(@me)

    assert_select "form[enctype='multipart/form-data']"
    assert_select "textarea[name='user[bio]'][maxlength='#{User::BIO_LENGTH}']"
    assert_select "input[type=file][name='user[avatar]']"
  end

  test "a saved bio shows under the name on the profile" do
    patch user_path(@me), params: { user: { bio: "Syklist fra Sandviken." } }

    follow_redirect!
    assert_select ".profile-header .profile-bio", text: "Syklist fra Sandviken."
  end

  test "a bio over the limit is refused" do
    patch user_path(@me), params: { user: { bio: "x" * (User::BIO_LENGTH + 1) } }

    assert_response :unprocessable_entity
    assert_nil @me.reload.bio
  end

  test "an uploaded photo replaces the identicon at the avatar address" do
    patch user_path(@me), params: { user: { avatar: photo } }

    assert photo_attached?
    get @me.avatar_url
    assert_response :redirect
    assert_match %r{/rails/active_storage/representations/}, response.location
  end

  test "a file that is not an image is refused" do
    patch user_path(@me), params: { user: { avatar: fixture_file_upload("tiny.mp4", "video/mp4") } }

    assert_response :unprocessable_entity
    refute photo_attached?
  end

  test "removing the photo brings the identicon back under a new address" do
    patch user_path(@me), params: { user: { avatar: photo } }
    with_photo = @me.reload.avatar_url

    travel 1.second do
      patch user_path(@me), params: { user: { remove_avatar: "1" } }
    end

    refute photo_attached?
    refute_equal with_photo, @me.reload.avatar_url
    get @me.avatar_url
    assert_equal "image/svg+xml", response.media_type
  end

  test "a departing account's photo is not served" do
    patch user_path(@me), params: { user: { avatar: photo } }
    @me.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get avatar_user_path(@me)

    assert_response :ok
    assert_equal "image/svg+xml", response.media_type
  end
end
