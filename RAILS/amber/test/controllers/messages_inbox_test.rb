# frozen_string_literal: true

require "test_helper"

# messages/index rendered its li rows straight into a <section>, which is
# invalid markup, and the first message sent through create.turbo_stream
# was prepended beside an empty state that never left. The inbox was then a
# flat list of every message; it is one row per person, and a row opens the
# messages with that person.
class MessagesInboxTest < ActionDispatch::IntegrationTest
  setup do
    @alice = user("alice")
    @bob = user("bob")
    @carol = user("carol")
    Connection.create!(requester: @alice, addressee: @bob, status: "accepted")
    Connection.create!(requester: @alice, addressee: @carol, status: "accepted")
    post session_path, params: { email_address: @alice.email_address, password: "password123" }
  end

  test "inbox rows are items of an ordered list" do
    Message.create!(sender: @bob, recipient: @alice, body: "Hei")

    get messages_path
    assert_response :success
    assert_select "ol#conversation-list > li.amber-conversation", 1
    assert_select "section > li", 0
    assert_select "#message-list-empty", 0
  end

  test "the inbox is one row per person, newest first, with the latest message and an unread dot" do
    Message.create!(sender: @bob, recipient: @alice, body: "First from Bob", created_at: 3.hours.ago)
    Message.create!(sender: @alice, recipient: @carol, body: "Hello Carol", created_at: 2.hours.ago,
                    read_at: Time.current)
    Message.create!(sender: @bob, recipient: @alice, body: "Latest from Bob", created_at: 1.hour.ago)

    get messages_path

    assert_select "ol#conversation-list > li", 2
    rows = css_select("ol#conversation-list > li")
    assert_equal [ "conversation_user_#{@bob.id}", "conversation_user_#{@carol.id}" ], rows.map { _1["id"] }
    assert_select "##{rows.first['id']} p", text: "Latest from Bob"
    assert_select "##{rows.first['id']} a[href=?]", messages_path(with: @bob.id), text: @bob.display_name
    assert_select "##{rows.first['id']} .amber-conversation-unread .visually-hidden", text: I18n.t("messages.unread")
    assert_select "##{rows.last['id']} p", text: I18n.t("messages.you_wrote", body: "Hello Carol")
    assert_select "##{rows.last['id']} .amber-conversation-unread", 0
    assert_select "li.amber-message", 0
  end

  test "a row opens the messages with that person alone, the composer addressed to them" do
    Message.create!(sender: @bob, recipient: @alice, body: "From Bob")
    Message.create!(sender: @alice, recipient: @carol, body: "To Carol")

    get messages_path(with: @bob.id)
    assert_response :success
    assert_select "h2", text: I18n.t("messages.conversation_with", name: @bob.display_name)
    assert_select "ol#message-list > li.amber-message", 1
    assert_select "ol#message-list", text: /From Bob/
    assert_select "select#message_recipient_id option[selected][value=?]", @bob.id.to_s
    assert_select "form#message-form input[type=hidden][name=with][value=?]", @bob.id.to_s
  end

  test "a person with no messages with the viewer opens nothing" do
    stranger = user("stranger")
    Message.create!(sender: stranger, recipient: @bob, body: "Not for Alice")

    get messages_path(with: stranger.id)
    assert_redirected_to messages_path
  end

  test "an empty inbox keeps a list to prepend into and drops the empty state on send" do
    get messages_path
    assert_select "ol#conversation-list", 1
    assert_select "#message-list-empty", 1

    post messages_path, params: { message: { recipient_id: @bob.id, body: "Hei" } }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(action="remove" target="message-list-empty")
    assert_includes response.body, %(action="prepend" target="conversation-list")
    refute_includes response.body, %(target="message-list")
  end

  test "a reply sent from a conversation joins it" do
    Message.create!(sender: @bob, recipient: @alice, body: "Hei")

    post messages_path, params: { with: @bob.id, message: { recipient_id: @bob.id, body: "Hei selv" } },
                        as: :turbo_stream
    assert_includes response.body, %(action="prepend" target="message-list")
    assert_includes response.body, %(name="with")
  end

  private

  def user(prefix)
    email = "#{prefix}-#{SecureRandom.hex(4)}@amber.test"
    User.strict_loading(false).create!(email_address: email, password: "password123")
  end
end
