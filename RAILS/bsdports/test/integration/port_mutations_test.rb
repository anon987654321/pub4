# frozen_string_literal: true

require "test_helper"

# Request-level coverage for bsdports watch/unwatch, explore, and comments.
class PortMutationsTest < ActionDispatch::IntegrationTest
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "net-mut", slug: "net-mut-#{SecureRandom.hex(3)}", description: "net")
    @port = Port.create!(
      platform: @platform,
      category: @category,
      name: "curl",
      pkgpath: "net/curl-mut-#{SecureRandom.hex(3)}",
      comment: "Tool for transferring data with URL syntax",
      version: "8.0.0",
      description: "libcurl client-side URL transfer library"
    )
  end

  def make_user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@bsdports.test",
      password: "password"
    )
  end

  def sign_in_bsdports(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  test "ports index and show are public" do
    get root_path
    assert_response :success

    get port_path(@port)
    assert_response :success
  end

  test "explore returns JSON summary" do
    get explore_port_path(@port), as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("summary") || body.key?("pkgpath")
  end

  test "watch and unwatch toggle for signed-in user" do
    user = make_user("watcher")
    sign_in_bsdports(user)

    assert_difference -> { Watch.count }, 1 do
      post watch_port_path(@port)
    end
    assert @port.watches.exists?(user_id: user.id)

    assert_difference -> { Watch.count }, -1 do
      delete unwatch_port_path(@port)
    end
  end

  test "authenticated user can comment on a port" do
    user = make_user("commenter")
    sign_in_bsdports(user)

    assert_difference -> { Comment.count }, 1 do
      post port_comments_path(@port), params: { comment: { content: "Works on 7.6" } }
    end
    comment = Comment.order(:id).last
    assert_equal user.id, comment.user_id
    assert_equal @port.id, comment.port_id
  end
end
