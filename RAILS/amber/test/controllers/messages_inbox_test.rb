# frozen_string_literal: true

require "test_helper"

# messages/index rendered its li rows straight into a <section>, which is
# invalid markup, and the first message sent through create.turbo_stream
# was prepended beside an empty state that never left.
class MessagesInboxTest < ActionDispatch::IntegrationTest
  setup do
    @alice = user("alice")
    @bob = user("bob")
    Connection.create!(requester: @alice, addressee: @bob, status: "accepted")
    post session_path, params: { email_address: @alice.email_address, password: "password123" }
  end

  test "inbox rows are items of an ordered list" do
    Message.create!(sender: @bob, recipient: @alice, body: "Hei")

    get messages_path
    assert_response :success
    assert_select "ol#message-list > li.amber-message", 1
    assert_select "section > li", 0
    assert_select "#message-list-empty", 0
  end

  test "an empty inbox keeps a list to prepend into and drops the empty state on send" do
    get messages_path
    assert_select "ol#message-list", 1
    assert_select "#message-list-empty", 1

    post messages_path, params: { message: { recipient_id: @bob.id, body: "Hei" } }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(action="remove" target="message-list-empty")
  end

  private

  def user(prefix)
    email = "#{prefix}-#{SecureRandom.hex(4)}@amber.test"
    User.strict_loading(false).create!(email_address: email, password: "password123")
  end
end
