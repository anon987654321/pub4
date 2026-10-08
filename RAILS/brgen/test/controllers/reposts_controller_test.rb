# frozen_string_literal: true

require "test_helper"

class RepostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(
      email_address: "rc_author@brgen.no", password: "password123", username: "rc_author", guest: false
    )
    @booster = User.strict_loading(false).create!(
      email_address: "rc_booster@brgen.no", password: "password123", username: "rc_booster", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @post = Post.create!(user: @author, title: "Torgallmenningen #{SecureRandom.hex(3)}", content: "Noe skjer")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "POST creates a repost and a second POST removes it" do
    sign_in_as(@booster)

    assert_difference -> { Repost.count }, 1 do
      post post_repost_path(@post)
    end
    assert_redirected_to root_path
    assert_equal 1, @post.reload.reposts_count

    # The action Stimulus controller only ever sends POST, so undo has to be the
    # same verb rather than a DELETE the front end will never issue.
    assert_difference -> { Repost.count }, -1 do
      post post_repost_path(@post)
    end
    assert_equal 0, @post.reload.reposts_count
  end

  # brgen mints a real User row for every cookieless visitor, and
  # require_user_session only asks for Current.user — so a guest can repost for
  # the same reason they can post and vote. Pinned because it is a deliberate
  # product position ("no signup required"), not an oversight, and the rate
  # limit rather than the session is what bounds it.
  test "a guest reposts like they post" do
    host! "brgen.no"

    assert_difference -> { Repost.count }, 1 do
      post post_repost_path(@post)
    end
  end

  test "POST with a comment creates a quote, and a second POST without one removes it" do
    sign_in_as(@booster)

    assert_difference -> { Repost.count }, 1 do
      post post_repost_path(@post), params: { comment: "Les dette" }
    end
    quote = Repost.find_by!(user: @booster, post: @post)
    assert_equal "Les dette", quote.comment

    post post_repost_path(@post), params: { comment: "Endret" }
    assert_equal "Endret", quote.reload.comment
    assert_equal 1, @post.reload.reposts_count

    assert_difference -> { Repost.count }, -1 do
      post post_repost_path(@post)
    end
  end

  test "a comment on an existing boost turns it into a quote" do
    sign_in_as(@booster)
    post post_repost_path(@post)

    assert_no_difference -> { Repost.count } do
      post post_repost_path(@post), params: { comment: "Etterpå" }
    end
    assert_equal "Etterpå", Repost.find_by!(user: @booster, post: @post).comment
  end

  test "a removed post cannot be reposted" do
    sign_in_as(@booster)
    @post.update!(removed_at: Time.current)

    assert_no_difference -> { Repost.count } do
      post post_repost_path(@post)
    end
    assert_response :not_found
  end

  # post_vote_path(post) carries the slug for the same reason, and find_votable
  # called Post.find on it — a 404 the action Stimulus controller rolls back
  # silently, so every vote cast from a feed card was discarded.
  test "voting on a post reaches it by slug" do
    sign_in_as(@booster)

    assert_difference -> { Vote.count }, 1 do
      post post_vote_path(@post), params: { vote: { value: 1 } }
    end
  end

  # The card is fragment-cached, and reposted_by? is user-specific output inside
  # it. Without the flag in the cache key, the first viewer's repost state is
  # served to everyone who loads the feed after them.
  test "one viewer's repost state does not leak into another's feed" do
    sign_in_as(@booster)
    post post_repost_path(@post)

    get root_path
    assert_response :success
    assert_match(/aria-pressed="true"/, response.body, "the booster should see their own repost as pressed")

    delete session_path if respond_to?(:delete)
    sign_in_as(@author)
    get root_path
    assert_response :success
    reposted_markup = response.body[/<button[^>]*post_repost[^>]*>/] || ""
    refute_match(/aria-pressed="true"/, reposted_markup,
                 "the author never reposted it; a cached fragment must not say otherwise")
  end
end
