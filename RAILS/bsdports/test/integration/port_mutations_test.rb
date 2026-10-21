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


  test "legacy executable homepage values render as text rather than links" do
    @port.update_column(:homepage, "javascript:alert(1)")

    get port_path(@port)

    assert_response :success
    assert_includes response.body, "javascript:alert(1)"
    refute_match(/href=["']javascript:alert\(1\)/i, response.body)
  end

  test "cross-port comment parents are rejected by controller and model" do
    user = make_user("thread-owner")
    other_port = Port.create!(
      platform: @platform, category: @category, name: "other",
      pkgpath: "net/other-#{SecureRandom.hex(3)}", version: "1"
    )
    parent = Comment.create!(user: user, port: other_port, content: "Parent on another port")
    child = Comment.new(user: user, port: @port, parent: parent, content: "Invalid reply")
    refute child.valid?
    assert child.errors[:parent_id].any?

    sign_in_bsdports(user)
    assert_no_difference "Comment.count" do
      post port_comments_path(@port), params: {
        comment: { content: "Cross-port reply", parent_id: parent.id }
      }
    end
    assert_response :unprocessable_entity
  end

  test "only the configured operator can queue NVD cross-reference work" do
    previous_admin = ENV["BSDPORTS_ADMIN_EMAIL"]
    ENV["BSDPORTS_ADMIN_EMAIL"] = "different-person@example.test"
    user = make_user("not-admin")
    sign_in_bsdports(user)

    post crossref_cves_port_path(@port)
    assert_response :forbidden
  ensure
    previous_admin.nil? ? ENV.delete("BSDPORTS_ADMIN_EMAIL") : ENV["BSDPORTS_ADMIN_EMAIL"] = previous_admin
  end

  test "configured operator enqueues NVD work without calling NVD in the request" do
    previous_admin = ENV["BSDPORTS_ADMIN_EMAIL"]
    user = make_user("bsdports-operator")
    ENV["BSDPORTS_ADMIN_EMAIL"] = user.email_address
    sign_in_bsdports(user)
    enqueued = nil

    NvdCveCrossrefJob.stub(:enqueue_for, ->(**arguments) { enqueued = arguments }) do
      post crossref_cves_port_path(@port)
    end

    assert_response :redirect
    assert_equal({ port_id: @port.id }, enqueued)
  ensure
    previous_admin.nil? ? ENV.delete("BSDPORTS_ADMIN_EMAIL") : ENV["BSDPORTS_ADMIN_EMAIL"] = previous_admin
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
