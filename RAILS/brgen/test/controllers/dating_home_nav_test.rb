# frozen_string_literal: true

require "test_helper"

# The dating home is the one page every dating route starts from, so what its
# nav offers, and to whom, decides which pages are reachable at all.
class DatingHomeNavTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @viewer = user_with_profile("dn_viewer", gender: "woman", looking_for: "man")
    @candidate = user_with_profile("dn_cand", gender: "man", looking_for: "woman")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user_with_profile(name, gender:, looking_for:)
    user = User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
    profile = Dating::Profile.new(user:, age: 30, gender:, looking_for:, visible: true, bio: "Hei")
    attach_pixel!(profile.photos, filename: "#{name}.png")
    profile.save!
    user
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "dating.brgen.no"
  end

  # The first visit is the splash; ?start=1 is what moves a reader to the deck.
  def open_deck
    get dating.root_path(start: 1)
    get dating.root_path
  end

  test "a signed-in member reaches likes, picks and verification from the home nav" do
    sign_in_as(@viewer)
    open_deck

    assert_response :success
    assert_select "header nav a[href=?]", dating.likes_path
    assert_select "header nav a[href=?]", dating.picks_path
    assert_select "header nav a[href=?]", dating.new_verification_path
  end

  # Pointer events already fire for touch; the touch bindings ran every
  # handler twice per touch.
  test "the deck binds pointer events only and carries a polite announcement" do
    sign_in_as(@viewer)
    open_deck

    deck = css_select(".dating-discover[data-controller=swipe]").first
    assert deck, "deck rendered"
    assert_not_includes deck["data-action"], "touchstart"
    assert_select ".dating-discover [data-swipe-target=announcement][aria-live=polite]"
    assert_select "[data-swipe-target=announcement][data-liked=?]", I18n.t("dating.announce_liked")
  end

  test "a verified profile carries its badge on the swipe card" do
    Dating::Profile.where(user_id: @candidate.id).update_all(verified_at: Time.current)
    sign_in_as(@viewer)
    open_deck

    assert_response :success
    assert_select ".swipe-card[data-user-id=?] .swipe-caption .chip", @candidate.id.to_s,
                  text: I18n.t("dating.verified")
  end

  test "matches list newest first" do
    older = user_with_profile("dn_older", gender: "man", looking_for: "woman")
    Dating::Match.create!(initiator: @viewer, receiver: older, status: "matched", created_at: 2.days.ago)
    Dating::Match.create!(initiator: @viewer, receiver: @candidate, status: "matched", created_at: 1.hour.ago)
    sign_in_as(@viewer)

    get dating.matches_path

    assert_response :success
    newer_at = response.body.index(@candidate.display_name)
    older_at = response.body.index(older.display_name)
    assert newer_at && older_at, "both matches listed"
    assert_operator newer_at, :<, older_at
  end

  test "the match overlay opens the conversation the match created" do
    conversation = Conversation.find_or_create_direct(@viewer, @candidate)
    html = ApplicationController.render(
      partial: "dating/matches/overlay",
      locals: { match: nil, current_user: @viewer, other_user: @candidate, conversation: }
    )

    assert_includes html, %(href="#{Rails.application.routes.url_helpers.conversation_path(conversation)}")
  end
end
