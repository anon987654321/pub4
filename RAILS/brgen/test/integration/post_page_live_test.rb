# frozen_string_literal: true

require "test_helper"

# posts#show reads its comments live, and nothing live may take a half-written
# comment away: the composer is permanent across the refresh an edit sends.
class PostPageLiveTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @reader = User.strict_loading(false).create!(
      email_address: "post-page-live@brgen.no", password: "password123", username: "leser", guest: false, city: @city
    )
    @post = Post.create!(user: @reader, city: @city, title: "Levende side", content: "Kommenter")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def stream_names(html)
    Nokogiri::HTML(html).css("turbo-cable-stream-source").map { |source| source["signed-stream-name"] }
  end

  test "the post page reads its comment thread" do
    get post_path(@post)

    assert_response :success
    assert_includes stream_names(response.body), Turbo::StreamsChannel.signed_stream_name([ @post, :comments ])
    assert_select "#comments-section[data-controller~=live-comments]"
  end

  test "the composer is permanent and keyed by the post" do
    post session_path, params: { email_address: @reader.email_address, password: "password123" }
    get post_path(@post)

    assert_select "#composer_post_#{@post.id}[data-turbo-permanent] form#comment_form"
  end

  test "the posts index reads its own city's stream" do
    get posts_path

    assert_response :success
    names = stream_names(response.body)
    assert_includes names, Turbo::StreamsChannel.signed_stream_name(Post.city_posts_stream(@city.id))
    assert_not_includes names, Turbo::StreamsChannel.signed_stream_name("posts")
  end
end
