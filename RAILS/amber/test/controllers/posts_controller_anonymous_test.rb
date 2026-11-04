# frozen_string_literal: true

require "test_helper"

class PostsControllerAnonymousTest < ActionDispatch::IntegrationTest
  def test_guest_can_post_anonymously_from_the_feed
    get posts_url
    assert_response :success
    assert_includes response.body, "amber-compose-box"

    assert_difference -> { Post.count }, 1 do
      post posts_url, params: { post: { body: "Loving this linen capsule #ootd", anonymous: true } }
    end

    assert_redirected_to root_url
    post = Post.includes(:user).order(:id).last
    assert post.anonymous?
    assert post.user.guest?
    assert_equal "Loving this linen capsule #ootd", post.body
  end

  # A rejected post comes back as the form with the writer's text and the
  # reason, not a redirect home that drops both.
  def test_rejected_post_keeps_the_text_and_shows_the_errors
    too_long = "camel coat " * 60

    assert_no_difference -> { Post.count } do
      post posts_url, params: { post: { body: too_long, anonymous: true } }
    end

    assert_response :unprocessable_content
    assert_select "form textarea[name='post[body]']" do |field|
      assert_includes field.text, "camel coat camel coat"
    end
  end

  def test_guest_feed_shows_actionable_empty_state_when_no_posts_exist
    Post.destroy_all

    get posts_url

    assert_response :success
    assert_select "section.empty-state[role=status]"
    assert_select "h2.empty-state-title", I18n.t("empty.no_posts_yet")
    assert_select "a.empty-state-action[href='#{new_post_path}']", I18n.t("empty.first_post")
    assert_includes response.body, "amber-compose-box"
  end

  # The inline compose box had no counter for its 500-character limit, which
  # posts/new shows, and three hashtag pills that looked tappable and did nothing.
  def test_the_feed_compose_box_counts_down_and_offers_no_dead_pills
    get posts_url
    box = "form.amber-compose-box"
    assert_select "#{box}[data-controller~=character-counter][data-character-counter-countdown-value=true]"
    assert_select "form.amber-compose-box textarea[maxlength=\"500\"][data-character-counter-target=input]"
    assert_select "form.amber-compose-box .char-counter[data-character-counter-target=counter][aria-live=polite]"
    assert_select ".amber-compose-tags", 0
  end
end
