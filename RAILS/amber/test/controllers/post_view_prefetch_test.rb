# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# posts#show recorded AmberPostViewed for every request, so a Turbo
# hover-prefetch counted as a view; bsdports already skips passive requests.
class PostViewPrefetchTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Safari/605.1.15" }.freeze

  setup do
    email = "pv-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    @post = Post.create!(user:, body: "Ny jakke")
  end

  test "a prefetch is not a view, a visit is" do
    actions = []
    recorder = ->(**args) { actions << args[:action].to_s }
    Shared::DomainEvent.stub(:record!, recorder) do
      get post_path(@post), headers: BROWSER.merge("Sec-Purpose" => "prefetch")
      assert_response :success
      assert_empty actions.grep(/viewed/)

      get post_path(@post), headers: BROWSER
      assert_equal 1, actions.grep(/viewed/).size
    end
  end
end
