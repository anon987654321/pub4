# frozen_string_literal: true

require "test_helper"

# Pages that must stay out of a search index say so: search results, the
# day-long stories, and the email preferences page whose URL is a token.
class RobotsNoindexTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def assert_noindex
    assert_response :success
    assert_select "head meta[name=robots][content=?]", "noindex, follow"
  end

  test "search results are noindex" do
    get global_search_path(q: "bryggen")
    assert_noindex
  end

  test "the stories ring is noindex" do
    get stories_path
    assert_noindex
  end

  test "the tokenised email preferences page is noindex" do
    subscription = EmailSubscription.create!(email: "robots@example.com")

    get email_subscription_path(token: subscription.token)
    assert_noindex
  end
end
