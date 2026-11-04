# frozen_string_literal: true

require "test_helper"

# Dating writes and pages: verification follows the photos, prompts stay the
# owner's and capped, a rejection can say why, and the crossings page speaks
# the locale.
class DatingRefinementsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @previous_slugs = Rails.application.config.x.oauth_provider_slugs
    Rails.application.config.x.oauth_provider_slugs = %w[vipps]
    @me = user_with_profile("dr_me")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Rails.application.config.x.oauth_provider_slugs = @previous_slugs
    ENV.delete("BRGEN_ADMIN_EMAIL")
  end

  def user_with_profile(handle)
    user = User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
    vipps = IdentityProvider.find_by(slug: "vipps") || IdentityProvider.create!(slug: "vipps", name: "Vipps")
    ExternalIdentity.create!(user:, identity_provider: vipps, subject: "sub-#{handle}", assurance_level: "verified")
    profile = Dating::Profile.new(user:, age: 30, bio: "hei", visible: true, gender: "woman", looking_for: "man")
    attach_pixel!(profile.photos, filename: "#{handle}.png")
    profile.save!
    user
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "dating.brgen.no"
  end

  def profile_for(user) = Dating::Profile.find_by!(user_id: user.id)

  def upload = Rack::Test::UploadedFile.new(StringIO.new(PIXEL_PNG), "image/png", true, original_filename: "ny.png")

  test "a new photo clears the verification the old ones earned" do
    profile_for(@me).update_columns(verified_at: Time.current)
    sign_in_as(@me)

    patch dating.profile_path, params: { profile: { photos: [ upload ] } }

    assert_nil profile_for(@me).verified_at
  end

  test "a fourth prompt is refused with the reason, and another's prompt cannot be removed" do
    profile = profile_for(@me)
    questions = Dating::Prompt::QUESTIONS.first(4)
    questions.first(3).each do |question|
      Dating::Prompt.create!(profile:, question:, answer: "svar")
    end
    other = profile_for(user_with_profile("dr_other")).prompts.create!(question: questions.first, answer: "mitt")
    sign_in_as(@me)

    assert_no_difference -> { Dating::Prompt.count } do
      post dating.profile_prompts_path, params: { prompt: { question: questions.last, answer: "en til" } }
    end
    assert flash[:alert].present?, "the refusal says why"

    assert_no_difference -> { Dating::Prompt.count } do
      delete dating.profile_prompt_path(other)
    end
    assert Dating::Prompt.exists?(other.id)
  end

  test "the reviewer can say why a verification was rejected" do
    admin = User.strict_loading(false).create!(email_address: "dr_admin@brgen.no", password: "password123",
                                               username: "dr_admin", guest: false)
    verification = profile_for(@me).verifications.new(pose: "thumbs_up")
    verification.selfie.attach(io: StringIO.new(PIXEL_PNG), filename: "s.png", content_type: "image/png")
    verification.save!
    ENV["BRGEN_ADMIN_EMAIL"] = admin.email_address
    sign_in_as(admin)

    get dating.verifications_path
    assert_select "form.verification-reject input[name=note]"

    patch dating.verification_path(verification), params: { decision: "reject", note: "Ansiktet er ikke synlig" }
    assert_equal "Ansiktet er ikke synlig", verification.reload.review_note
  end

  test "reading the crossings page writes nothing" do
    other = user_with_profile("dr_expired")
    Dating::LocationPing.create!(city: @city, user: other, latitude: 60.392, longitude: 5.323, expires_at: 1.minute.ago)
    sign_in_as(@me)

    assert_no_difference -> { Dating::LocationPing.count } do
      get dating.path_crossings_path
    end
  end

  test "a crossing is dated in a time element with ago" do
    other = user_with_profile("dr_cross")
    Dating::Profile.where(user_id: [ @me.id, other.id ])
                   .update_all(verified_at: Time.current, location_discovery_enabled: true)
    crossed = 7.minutes.ago
    a, b = [ @me.id, other.id ].sort
    Dating::PathCrossing.create!(city: @city, user_a_id: a, user_b_id: b, crossed_at: crossed,
                                 crossing_on: crossed.to_date, approx_latitude: 60.39, approx_longitude: 5.32)
    sign_in_as(@me)

    get dating.path_crossings_path
    assert_response :success
    ago = ApplicationController.helpers.time_ago_in_words(crossed)
    assert_select "time[datetime]", text: I18n.t("dating.crossed_ago", time: ago)
    assert_select "[data-controller=dating-location][data-dating-location-waiting-value=?]",
                  I18n.t("dating.location_status.waiting")
  end
end
