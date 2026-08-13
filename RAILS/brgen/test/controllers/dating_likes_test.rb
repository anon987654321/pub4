# frozen_string_literal: true

require "test_helper"

class DatingLikesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    # Before the profiles: Dating::Profile is CityTenantable, so one created
    # without a tenant gets city_id nil and then reads differently once a tenant
    # is set.
    ActsAsTenant.current_tenant = @city
    @me = user_with_profile("me")
    @them = user_with_profile("them")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def user_with_profile(handle)
    user = User.strict_loading(false).create!(
      email_address: "dl_#{handle}@brgen.no", password: "password123",
      username: "dl_#{handle}", guest: false, city: @city
    )
    Dating::Profile.create!(user: user, age: 30, bio: "hei", visible: true)
    user
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def in_dating = host!("dating.brgen.no")

  test "a like can carry a prompt and a sentence about it" do
    prompt = Dating::Prompt.create!(
      profile: @them.dating_profile, question: Dating::Prompt::QUESTIONS.first, answer: "Fjelltur"
    )
    sign_in_as(@me)
    in_dating

    post dating.likes_path, params: { user_id: @them.id, prompt_id: prompt.id, comment: "Hvilket fjell?" }

    like = Dating::Like.find_by(liker_id: @me.id, likee_id: @them.id)
    assert_equal prompt.id, like.dating_prompt_id
    assert_equal "Hvilket fjell?", like.comment
  end

  # Scoped to the liked person's own prompts, or a like can be pointed at
  # somebody else's answer entirely.
  test "a like cannot point at a prompt belonging to someone else" do
    stranger = user_with_profile("stranger")
    theirs = Dating::Prompt.create!(
      profile: stranger.dating_profile, question: Dating::Prompt::QUESTIONS.first, answer: "Ikke min"
    )
    sign_in_as(@me)
    in_dating

    post dating.likes_path, params: { user_id: @them.id, prompt_id: theirs.id, comment: "hei" }

    assert_nil Dating::Like.find_by(liker_id: @me.id, likee_id: @them.id).dating_prompt_id
  end

  test "a plain like with no comment is still a like" do
    sign_in_as(@me)
    in_dating

    assert_difference -> { Dating::Like.count }, 1 do
      post dating.likes_path, params: { user_id: @them.id }
    end
  end

  test "who liked you lists people waiting and drops the ones already answered" do
    waiting = user_with_profile("waiting")
    answered = user_with_profile("answered")
    Dating::Like.create!(liker: waiting, likee: @me, comment: "hei")
    Dating::Like.create!(liker: answered, likee: @me)
    Dating::Like.create!(liker: @me, likee: answered)

    sign_in_as(@me)
    in_dating
    get dating.likes_path

    assert_response :success
    assert_match waiting.dating_profile.name, response.body
    refute_match answered.dating_profile.name, response.body,
                 "a list that keeps showing people you already matched with is one nobody opens twice"
  end

  test "someone you passed on does not come back in who-liked-you" do
    passed = user_with_profile("passed")
    Dating::Like.create!(liker: passed, likee: @me)
    Dating::Dislike.create!(disliker: @me, dislikee: passed)

    assert_empty Dating::Like.waiting_on(@me).to_a
  end
end
