# frozen_string_literal: true

require "test_helper"

class CrosspostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = create_user("xp_author")
    @stranger = create_user("xp_stranger")
    ActsAsTenant.current_tenant = @city
    @home = Community.create!(name: "Bergen sykkel #{SecureRandom.hex(2)}", slug: "xp-home-#{SecureRandom.hex(3)}")
    @other = Community.create!(name: "Bergen marked #{SecureRandom.hex(2)}", slug: "xp-other-#{SecureRandom.hex(3)}")
    @post = Post.create!(user: @author, community: @home, title: "Sykkelsti #{SecureRandom.hex(3)}", content: "Ny sti i Fyllingsdalen")
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

  test "a crosspost is its own post in the second community" do
    sign_in_as(@author)

    assert_difference -> { Post.count }, 1 do
      post post_crossposts_path(@post), params: { community_id: @other.slug }
    end
    crosspost = Post.order(:created_at).last
    assert_equal @other.id, crosspost.community_id
    assert_equal @post.id, crosspost.crossposted_from_id
    assert_equal @post.title, crosspost.title
    assert_equal 1, @post.reload.crossposts_count
    # Its own thread: a comment here is not a comment there.
    assert_equal 0, crosspost.comments_count
  end

  # A chain would make "seen in four communities" unanswerable without walking
  # it, so a crosspost of a crosspost points at the original.
  test "crossposting a crosspost points at the original" do
    sign_in_as(@author)
    post post_crossposts_path(@post), params: { community_id: @other.slug }
    crosspost = Post.order(:created_at).last
    third = Community.create!(name: "Bergen mat #{SecureRandom.hex(2)}", slug: "xp-third-#{SecureRandom.hex(3)}")

    post post_crossposts_path(crosspost), params: { community_id: third.slug }
    assert_equal @post.id, Post.order(:created_at).last.crossposted_from_id
    assert_equal 2, @post.reload.crossposts_count
  end

  test "the same community twice is refused, and so is its own" do
    sign_in_as(@author)
    post post_crossposts_path(@post), params: { community_id: @other.slug }

    assert_no_difference -> { Post.count } do
      post post_crossposts_path(@post), params: { community_id: @other.slug }
      post post_crossposts_path(@post), params: { community_id: @home.slug }
    end
  end

  # postable_by? reads bans before privacy, which is the whole point of checking
  # it here rather than membership.
  test "a ban in the target community stops the crosspost" do
    CommunityBan.create!(community: @other, user: @stranger, banned_by: @author, reason: "spam")
    sign_in_as(@stranger)

    assert_no_difference -> { Post.count } do
      post post_crossposts_path(@post), params: { community_id: @other.slug }
    end
  end

  test "the post page offers the communities the reader can still reach" do
    sign_in_as(@author)

    get post_path(@post)
    assert_response :success
    assert_includes response.body, post_crossposts_path(@post)
    assert_includes response.body, @other.slug
  end
end
