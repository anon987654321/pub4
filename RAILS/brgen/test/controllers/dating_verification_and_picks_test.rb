# frozen_string_literal: true

require "test_helper"

class DatingVerificationAndPicksTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @viewer = user_with_profile("dv_viewer", gender: "woman", looking_for: "man")
    @candidates = 7.times.map { |i| user_with_profile("dv_cand#{i}", gender: "man", looking_for: "woman") }
    @admin = User.strict_loading(false).create!(
      email_address: "dv_admin@brgen.no", password: "password123", username: "dv_admin", guest: false
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    ENV.delete("BRGEN_ADMIN_EMAIL")
  end

  def user_with_profile(name, gender:, looking_for:)
    user = User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
    profile = Dating::Profile.new(user: user, age: 30, gender: gender, looking_for: looking_for, visible: true, bio: "Hei")
    attach_pixel!(profile.photos, filename: "#{name}.png")
    profile.save!
    user
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "dating.brgen.no"
  end

  def profile_for(user) = Dating::Profile.find_by!(user_id: user.id)

  test "a verification asks for a pose and carries it into the review" do
    sign_in_as(@viewer)

    get dating.new_verification_path
    assert_response :success
    pose = response.body[/name="verification\[pose\]"[^>]*value="([a-z_]+)"/, 1] ||
           response.body[/value="([a-z_]+)"[^>]*name="verification\[pose\]"/, 1]
    assert_includes Dating::Verification::POSES, pose

    assert_difference -> { Dating::Verification.count }, 1 do
      post dating.verifications_path, params: {
        verification: { pose: pose, selfie: fixture_selfie }
      }
    end
    assert_equal pose, Dating::Verification.order(:created_at).last.pose
  end

  test "a selfie is required and one request at a time" do
    profile = profile_for(@viewer)
    bare = profile.verifications.new(pose: "thumbs_up")
    assert_not bare.valid?

    first = profile.verifications.new(pose: "thumbs_up")
    first.selfie.attach(io: StringIO.new(PIXEL_PNG), filename: "s.png", content_type: "image/png")
    first.save!

    second = profile.verifications.new(pose: "palm_out")
    second.selfie.attach(io: StringIO.new(PIXEL_PNG), filename: "s2.png", content_type: "image/png")
    assert_not second.valid?
  end

  # A person reviews, and only the admin the moderation queue already names.
  test "only the admin reviews, and approval marks the profile" do
    profile = profile_for(@viewer)
    verification = profile.verifications.new(pose: "peace_sign")
    verification.selfie.attach(io: StringIO.new(PIXEL_PNG), filename: "s.png", content_type: "image/png")
    verification.save!

    sign_in_as(@viewer)
    get dating.verifications_path
    assert_response :forbidden

    ENV["BRGEN_ADMIN_EMAIL"] = @admin.email_address
    sign_in_as(@admin)
    get dating.verifications_path
    assert_response :success

    patch dating.verification_path(verification, decision: "approve")
    assert_equal "verified", verification.reload.status
    assert_not_nil profile.reload.verified_at
    assert Notification.where(user_id: @viewer.id, kind: "alert").exists?
  end

  test "a blank admin address makes nobody a reviewer" do
    ENV["BRGEN_ADMIN_EMAIL"] = ""
    sign_in_as(@admin)

    get dating.verifications_path
    assert_response :forbidden
  end

  # The point of a daily list is that it is the same list all day.
  test "today's picks are drawn once and stay put" do
    sign_in_as(@viewer)

    get dating.picks_path
    assert_response :success
    first_ids = Dating::DailyPick.where(user_id: @viewer.id, picked_on: Date.current).pluck(:profile_id)
    assert_equal Dating::DailyPick::PER_DAY, first_ids.size

    get dating.picks_path
    assert_equal first_ids.sort, Dating::DailyPick.where(user_id: @viewer.id, picked_on: Date.current).pluck(:profile_id).sort
  end

  # And that tomorrow's is different.
  test "tomorrow does not repeat this week's faces" do
    sign_in_as(@viewer)
    get dating.picks_path
    today = Dating::DailyPick.where(user_id: @viewer.id, picked_on: Date.current).pluck(:profile_id)

    travel 1.day
    get dating.picks_path
    tomorrow = Dating::DailyPick.where(user_id: @viewer.id, picked_on: Date.current).pluck(:profile_id)

    assert_empty (today & tomorrow), "the same faces came back the next day"
  end

  def fixture_selfie
    Rack::Test::UploadedFile.new(StringIO.new(PIXEL_PNG), "image/png", true, original_filename: "selfie.png")
  end
end
