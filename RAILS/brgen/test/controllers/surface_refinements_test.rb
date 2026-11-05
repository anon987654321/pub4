# frozen_string_literal: true

require "test_helper"

# Small reachability and landmark fixes across brgen's own surfaces: stories,
# the mobile chrome, the onboarding dialog and the email preferences page.
class SurfaceRefinementsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = member("sr_author")
    @viewer = member("sr_viewer")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false
    )
  end

  def story_by(user)
    story = Story.new(user:, caption: "Bryggen")
    story.media.attach(ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-jpeg-bytes"), filename: "snap.jpg", content_type: "image/jpeg", identify: false
    ))
    story.save!
    story
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a viewer can report someone else's story" do
    story = story_by(@author)
    sign_in_as(@viewer)

    get story_path(story)
    assert_response :success
    assert_select "form[action=?]", reports_path
  end

  test "a story ring's name carries its count and seen state" do
    2.times { story_by(@author) }

    get stories_path
    assert_response :success
    ring = css_select(".story-ring a").first
    assert_includes ring["aria-label"], I18n.t("stories.ring_count", count: 2)
    assert_includes ring["aria-label"], I18n.t("stories.ring_unseen")
    assert_equal "320", ring.at_css("img")["height"]
  end

  test "the More sheet links the account page and the tab bar re-marks its current tab" do
    sign_in_as(@viewer)

    get root_path
    assert_select ".mobile-sheet-links a[href=?]", account_path
    # scroll-chrome owns the bar and re-marks its current tab after each visit.
    assert_select "[data-controller~=scroll-chrome] nav#app-tab-bar[data-scroll-chrome-target=bar]"
  end

  test "the onboarding dialog titles itself below the page heading, with decorative art" do
    get root_path

    assert_select ".welcome-onboarding h2[id^=welcome-onboarding-title]"
    assert_select ".welcome-onboarding h1", 0
    css_select(".welcome-onboarding-art img").each { |img| assert_equal "", img["alt"] }
  end

  test "email preferences sit inside the layout's one main landmark" do
    subscription = EmailSubscription.create!(email: "landmark@example.com")

    get email_subscription_path(token: subscription.token)
    assert_response :success
    assert_select "main", 1
  end

  test "the account page links email preferences when the address subscribes" do
    subscription = EmailSubscription.create!(email: @viewer.email_address)
    sign_in_as(@viewer)

    get account_path
    assert_response :success
    assert_select ".account-settings a[href=?]", email_subscription_path(token: subscription.token)
  end
end
