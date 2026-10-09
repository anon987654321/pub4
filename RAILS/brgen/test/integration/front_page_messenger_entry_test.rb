# frozen_string_literal: true

require "test_helper"

# The front page is where the messenger is found. On a phone the tab bar rests
# hidden, so the entry has to be on the page itself, labelled in Norwegian, with
# the unread count the reader would otherwise have to open the inbox to learn.
class FrontPageMessengerEntryTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = create_user("front_user")
    @friend = create_user("front_friend")
    @conversation = Conversation.find_or_create_direct(@user, @friend)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def entry(html)
    Nokogiri::HTML(html).at_css(%(.home-feed-views a[href="#{conversations_path}"]))
  end

  test "the front page links to the inbox with the Norwegian label" do
    sign_in_as(@user)
    get root_path

    assert_response :success
    assert entry(response.body), "no messenger link in the front-page nav"
    assert_includes entry(response.body).text, I18n.t("nav.messages", locale: :nb)
  end

  test "no badge when nothing is unread" do
    sign_in_as(@user)
    get root_path

    assert_nil entry(response.body).at_css(".nav_link_badge")
  end

  test "the badge carries the unread count and is spoken as words" do
    3.times { @conversation.messages.create!(sender: @friend, content: "Hei", message_type: "text") }
    sign_in_as(@user)
    get root_path

    link = entry(response.body)
    assert_equal "3", link.at_css(".nav_link_badge").text
    assert_includes link.text, I18n.t("messages.unread_badge", count: 3)
  end

  test "a muted thread stays out of the badge" do
    @conversation.messages.create!(sender: @friend, content: "Hei", message_type: "text")
    ConversationParticipant.find_by!(conversation: @conversation, user: @user).update!(muted_at: Time.current)
    sign_in_as(@user)
    get root_path

    assert_nil entry(response.body).at_css(".nav_link_badge")
  end

  test "the swiper's Messenger entry wears the same count" do
    2.times { @conversation.messages.create!(sender: @friend, content: "Hei", message_type: "text") }
    sign_in_as(@user)
    get root_path

    swiper = Nokogiri::HTML(response.body).css("#nav_sections .nav_link_badge").map(&:text)
    assert_includes swiper, "2"
  end

  test "a signed-out visitor sees the link and no count" do
    host! "brgen.no"
    get root_path

    assert_response :success
    assert entry(response.body)
    assert_nil entry(response.body).at_css(".nav_link_badge")
  end

  test "the front page labels carry no English fallbacks" do
    sign_in_as(@user)
    get root_path

    nav = Nokogiri::HTML(response.body).at_css(".home-feed-views")
    assert_equal I18n.t("home.feed_views", locale: :nb), nav["aria-label"]
    assert_includes nav.text, I18n.t("home.media_wall_view", locale: :nb)
  end
end
