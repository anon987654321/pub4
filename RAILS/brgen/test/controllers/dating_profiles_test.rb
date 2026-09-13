# frozen_string_literal: true

require "test_helper"

class DatingProfilesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = user_with_profile("dp_me", visible: false)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def user_with_profile(handle, visible: true, gender: "woman", looking_for: "man")
    user = User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123",
      username: handle, guest: false, city: @city
    )
    profile = Dating::Profile.new(user: user, age: 30, bio: "hei", visible: visible, gender: gender, looking_for: looking_for)
    attach_pixel!(profile.photos, filename: "#{handle}.png")
    profile.save!
    user
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "dating.brgen.no"
  end

  def profile_for(user) = Dating::Profile.includes(photos_attachments: :blob).find_by!(user_id: user.id)

  def upload(content_type: "image/png", filename: "ny.png")
    Rack::Test::UploadedFile.new(StringIO.new(PIXEL_PNG), content_type, true, original_filename: filename)
  end

  # A multiple file field always posts an empty value, and assigning that to a
  # has_many_attached deletes the set.
  test "saving the profile without new photos keeps the ones it has" do
    sign_in_as(@me)

    patch dating.profile_path, params: { profile: { bio: "ny bio", photos: [ "" ] } }

    assert_redirected_to dating.root_path
    assert_equal 1, profile_for(@me).photos.size
  end

  test "a new photo joins the set rather than replacing it" do
    sign_in_as(@me)

    patch dating.profile_path, params: { profile: { photos: [ upload ] } }

    assert_equal 2, profile_for(@me).photos.size
  end

  test "a ticked photo is removed and the others stay" do
    attach_pixel!(profile_for(@me).photos, filename: "second.png")
    photos = profile_for(@me).photos.sort_by(&:id)
    sign_in_as(@me)

    get dating.edit_profile_path
    assert_select "input[type=checkbox][name='profile[remove_photo_ids][]'][value='#{photos.first.id}']"

    patch dating.profile_path, params: { profile: { remove_photo_ids: [ photos.first.id ] } }

    assert_equal [ photos.last.id ], profile_for(@me).photos.map(&:id)
  end

  test "an upload MediaGuard refuses saves nothing" do
    sign_in_as(@me)

    patch dating.profile_path, params: { profile: { bio: "endret", photos: [ upload(content_type: "text/plain", filename: "x.txt") ] } }

    assert_response :unprocessable_entity
    assert_equal 1, profile_for(@me).photos.size
    assert_equal "hei", profile_for(@me).bio
  end

  test "the details tab speaks through the locale, not the stored identifiers" do
    sign_in_as(@me)

    get dating.profile_path

    assert_response :success
    assert_includes response.body, I18n.t("dating.genders.woman", locale: :nb)
    assert_includes response.body, I18n.t("dating.looking_for_options.man", locale: :nb)
    assert_includes response.body, I18n.t("dating.hidden_note", locale: :nb)
  end

  test "the profile form offers translated choices and asks for age up front" do
    sign_in_as(@me)

    get dating.edit_profile_path

    assert_select "select[name='profile[gender]'] option[value=woman]", text: I18n.t("dating.genders.woman", locale: :nb)
    assert_select "select[name='profile[looking_for]'] option[value=everyone]", text: I18n.t("dating.looking_for_options.everyone", locale: :nb)
    assert_select "fieldset.dating-profile-essentials input[name='profile[age]'][required]"
    assert_select "details.dating-profile-more input[name='profile[age]']", count: 0
  end

  test "a like reaches only someone the deck could show" do
    hidden = user_with_profile("dp_hidden", visible: false)
    sign_in_as(user_with_profile("dp_liker"))

    assert_no_difference -> { Dating::Like.count } do
      post dating.likes_path, params: { user_id: hidden.id }
    end
    assert_response :not_found
  end

  test "a like that fails validation redirects with the reason instead of erroring" do
    them = user_with_profile("dp_them")
    sign_in_as(user_with_profile("dp_wordy"))

    assert_no_difference -> { Dating::Like.count } do
      post dating.likes_path, params: { user_id: them.id, comment: "x" * 300 }, headers: { "HTTP_REFERER" => dating.root_url }
    end
    assert_response :redirect
    assert flash[:alert].present?
  end

  test "the deck leaves out everyone already liked or passed" do
    viewer = user_with_profile("dp_viewer", gender: "man", looking_for: "woman")
    liked = user_with_profile("dp_liked")
    passed = user_with_profile("dp_passed")
    fresh = user_with_profile("dp_fresh")
    Dating::Like.create!(liker: viewer, likee: liked)
    Dating::Dislike.create!(disliker: viewer, dislikee: passed)
    sign_in_as(viewer)

    get dating.root_path

    assert_response :success
    assert_includes response.body, fresh.display_name
    refute_includes response.body, liked.display_name
    refute_includes response.body, passed.display_name
  end
end
