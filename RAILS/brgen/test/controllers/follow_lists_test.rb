# frozen_string_literal: true

require "test_helper"

# A profile's follower and following counts lead to the people behind them.
class FollowListsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
    @kari = person("kari")
    @ola = person("ola")
    @per = person("per")

    @ola.follow!(@kari)
    @per.follow!(@kari)
    @kari.follow!(@ola)
  end

  def person(name)
    handle = "#{name}_#{SecureRandom.hex(3)}"
    User.create!(email_address: "#{handle}@brgen.no", password: "password123", username: handle)
  end

  test "the profile's counts link to the two lists" do
    get user_path(@kari)

    assert_select ".profile-header a[href=?]", user_followers_path(@kari),
                  text: I18n.t("profile.followers", count: 2)
    assert_select ".profile-header a[href=?]", user_following_path(@kari),
                  text: I18n.t("profile.following", count: 1)
  end

  test "the followers list names each follower and links their profile" do
    get user_followers_path(@kari)

    assert_response :success
    assert_select "h1", text: I18n.t("follow_lists.followers_title", name: @kari.display_name)
    assert_select ".people-list a[href=?]", user_path(@ola)
    assert_select ".people-list a[href=?]", user_path(@per)
    assert_select ".people-list li", 2
  end

  test "the following list names whom the person follows" do
    get user_following_path(@kari)

    assert_select ".people-list a[href=?]", user_path(@ola)
    assert_select ".people-list li", 1
  end

  test "a departing follower is not listed" do
    @per.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get user_followers_path(@kari)

    assert_select ".people-list a[href=?]", user_path(@per), count: 0
  end

  test "a reader blocked by a follower does not see that follower" do
    Block.create!(blocker: @per, blocked: @ola)
    post session_path, params: { email_address: @ola.email_address, password: "password123" }

    get user_followers_path(@kari)

    assert_select ".people-list a[href=?]", user_path(@per), count: 0
  end

  test "an empty list says so" do
    loner = person("alene")
    get user_following_path(loner)

    assert_select ".empty-state-title", text: I18n.t("follow_lists.following_empty", name: loner.display_name)
  end

  # fediverse_test proves the collection itself; this proves the HTML list
  # does not take its requests.
  test "an ActivityPub request for followers is not answered with the HTML list" do
    get "/users/#{@kari.username}/followers", headers: { "Accept" => "application/activity+json" }

    refute_includes response.body, I18n.t("follow_lists.followers_title", name: @kari.display_name)
  end
end
