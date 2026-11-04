# frozen_string_literal: true

require "test_helper"

# A pending request offered only Accept and Block, so turning a stranger
# down meant blocking them; rows named the other person without a picture or
# a link; and an accepted connection gave no way to write to them.
class ConnectionRowsTest < ActionDispatch::IntegrationTest
  setup do
    @me = member("me")
    @stranger = member("stranger")
    @friend = member("friend")
    post session_path, params: { email_address: @me.email_address, password: "password" }
    @pending = Connection.create!(requester: @stranger, addressee: @me, status: "pending")
    Connection.create!(requester: @me, addressee: @friend, status: "accepted")
  end

  def member(name)
    email = "#{name}-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
  end

  test "a pending request can be declined without blocking" do
    get connections_path
    assert_select "form[action=?] input[name=decline]", connection_path(@pending)

    patch connection_path(@pending), params: { decline: true }
    assert_redirected_to connections_path
    assert_not Connection.exists?(@pending.id), "a declined request stays"
    assert_equal I18n.t("flash.connection_declined"), flash[:notice]
  end

  test "rows link to the other person and an accepted one offers a message" do
    get connections_path
    assert_select "article a[href=?]", user_path(@stranger)
    assert_select "article .avatar-initials", 2
    assert_select "article a[href=?]", messages_path(recipient_id: @friend.id), text: I18n.t("actions.message")
    assert_select "article a[href=?]", messages_path(recipient_id: @stranger.id), 0

    get messages_path(recipient_id: @friend.id)
    assert_response :success
    assert_select "select[name='message[recipient_id]'] option[selected][value=?]", @friend.id.to_s
  end
end
