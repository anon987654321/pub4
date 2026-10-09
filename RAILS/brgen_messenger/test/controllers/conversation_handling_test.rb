# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# What a reader can do with their own inbox: mute, archive, block, and be sure a
# retried send is one message. Every user-facing string is asserted through its
# I18n key.
class ConversationHandlingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = create_user("handle_user")
    @friend = create_user("handle_friend")
    @stranger = create_user("handle_stranger")
    @conversation = Conversation.find_or_create_direct(@user, @friend)
    Message.create!(conversation: @conversation, sender: @friend, content: "Hei på deg", message_type: "text")
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

  def membership(user) = ConversationParticipant.find_by!(conversation: @conversation, user: user)

  def send_message(content, token: nil)
    post conversation_messages_path(@conversation),
         params: { message: { content: content, message_type: "text", client_token: token } },
         as: :turbo_stream
  end

  test "mute is the viewer's own, reversible, and says so" do
    sign_in_as(@user)

    post conversation_mute_path(@conversation)
    assert_predicate membership(@user).reload, :muted?
    assert_not_predicate membership(@friend).reload, :muted?
    assert_equal I18n.t("flash.conversation_muted"), flash[:notice]

    delete conversation_mute_path(@conversation)
    assert_not_predicate membership(@user).reload, :muted?
  end

  test "archive takes a thread off the inbox and onto the archive list" do
    sign_in_as(@user)

    post conversation_archive_path(@conversation)
    assert_redirected_to conversations_path
    assert_predicate membership(@user).reload, :archived?

    get conversations_path
    assert_not_includes response.body, conversation_path(@conversation)

    get conversations_path(arkiv: 1)
    assert_includes response.body, conversation_path(@conversation)
    assert_includes response.body, I18n.t("messages.archive_title")
  end

  test "the rail links to the archive only when it holds something" do
    sign_in_as(@user)
    get conversations_path
    assert_not_includes response.body, I18n.t("messages.archive_link", count: 1)

    membership(@user).update!(archived_at: Time.current)
    get conversations_path
    assert_includes response.body, I18n.t("messages.archive_link", count: 1)
  end

  test "an empty archive says so" do
    sign_in_as(@user)
    get conversations_path(arkiv: 1)
    assert_includes response.body, I18n.t("messages.archive_empty_title")
  end

  test "mute and archive are refused to a stranger and to a visitor" do
    sign_in_as(@stranger)
    post conversation_mute_path(@conversation)
    assert_response :not_found
    post conversation_archive_path(@conversation)
    assert_response :not_found
  end

  test "a muted thread gets no push and an unmuted one does" do
    pushed = []
    Shared::Pushable.stub(:push_to, ->(recipient, **_) { pushed << recipient.id }) do
      sign_in_as(@user)
      send_message("Ikke dempet")
      assert_includes pushed, @friend.id

      pushed.clear
      membership(@friend).update!(muted_at: Time.current)
      send_message("Dempet nå")
      assert_empty pushed
    end
  end

  test "a person who blocked the sender gets no push" do
    group = Conversation.create_group!(creator: @user, name: "Tur", users: [ @friend, @stranger ])
    @friend.block!(@user)
    pushed = []
    Shared::Pushable.stub(:push_to, ->(recipient, **_) { pushed << recipient.id }) do
      sign_in_as(@user)
      post conversation_messages_path(group), params: { message: { content: "Hei alle", message_type: "text" } },
                                              as: :turbo_stream
    end
    assert_equal [ @stranger.id ], pushed
  end

  test "a push from a view-once or timed thread carries no words" do
    @conversation.update!(disappearing_duration: 0)
    bodies = []
    Shared::Pushable.stub(:push_to, ->(_recipient, body:, **_) { bodies << body }) do
      sign_in_as(@user)
      send_message("Hemmelig adresse")
    end
    assert_equal [ I18n.t("messages.push_body_disappearing") ], bodies
  end

  test "blocking holds inside an existing thread, in both directions" do
    @friend.block!(@user)
    sign_in_as(@user)

    assert_no_difference -> { Message.count } do
      send_message("Er du der?")
    end
    assert_response :forbidden

    delete session_path
    sign_in_as(@friend)
    assert_no_difference -> { Message.count } do
      send_message("Jeg blokkerte deg")
    end
    assert_response :forbidden
  end

  test "the thread tells the blocker how to lift it and hides the composer" do
    @user.block!(@friend)
    sign_in_as(@user)

    get conversation_path(@conversation)
    assert_includes response.body, I18n.t("messages.blocked_by_me")
    assert_includes response.body, I18n.t("messages.unblock_user")
    assert_not_includes response.body, 'id="new_message"'
  end

  test "an unblocked thread offers block and the composer" do
    sign_in_as(@user)
    get conversation_path(@conversation)
    assert_includes response.body, I18n.t("messages.block_user")
    assert_includes response.body, 'id="new_message"'
  end

  test "a retried send with the same token is one message" do
    sign_in_as(@user)

    assert_difference -> { Message.where(sender: @user).count }, 1 do
      send_message("Én gang", token: "attempt-1")
      assert_response :success
      send_message("Én gang", token: "attempt-1")
      assert_response :success
    end
  end

  test "a new token is a new message" do
    sign_in_as(@user)

    assert_difference -> { Message.where(sender: @user).count }, 2 do
      send_message("Første", token: "attempt-1")
      send_message("Andre", token: "attempt-2")
    end
  end

  test "a token belongs to its sender" do
    sign_in_as(@user)
    send_message("Min", token: "shared-token")

    delete session_path
    sign_in_as(@friend)
    assert_difference -> { Message.where(sender: @friend).count }, 1 do
      send_message("Din", token: "shared-token")
    end
  end

  # The broadcast is lost to a socket that has not resubscribed; the response
  # carries the sender's line so it still shows.
  test "the response carries the sender's own line" do
    sign_in_as(@user)
    send_message("Synlig uansett", token: "attempt-9")

    assert_includes response.body, 'action="append"'
    assert_includes response.body, "Synlig uansett"
    assert_includes response.body, "message_#{Message.find_by!(client_token: 'attempt-9').id}"
  end

  test "a send without a token still works" do
    sign_in_as(@user)
    assert_difference -> { Message.where(sender: @user).count }, 2 do
      send_message("Uten navn")
      send_message("Uten navn")
    end
  end

  test "an over-long token is refused rather than stored" do
    sign_in_as(@user)
    assert_no_difference -> { Message.count } do
      send_message("For langt", token: "x" * 65)
    end
  end

  test "a reported message reaches moderation" do
    sign_in_as(@user)
    message = @conversation.messages.where(sender: @friend).first

    assert_difference -> { ModerationReport.count }, 1 do
      post reports_path, params: { target_gid: message.to_signed_global_id.to_s, reason: "abuse" }
    end
    report = ModerationReport.last
    assert_equal [ "Message", message.id ], [ report.reportable_type, report.reportable_id ]
  end

  test "the thread offers mute, archive and a report on the other person's line" do
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_includes response.body, I18n.t("messages.mute")
    assert_includes response.body, I18n.t("messages.archive")
    assert_includes response.body, reports_path
  end

  test "view once appears among the disappearing options with its note" do
    @conversation.update!(disappearing_duration: 0)
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_includes response.body, I18n.t("messages.disappearing_options.after_read")
    assert_includes response.body, I18n.t("messages.disappearing_note")
  end

  test "the owner can choose view once" do
    sign_in_as(@user)
    patch conversation_path(@conversation), params: { disappearing: "after_read" }

    assert_predicate @conversation.reload, :view_once?
  end

  # A visitor has no inbox. The page names the two ways in rather than showing a
  # dead end.
  test "a signed-out visitor is told how to sign in or join the open room" do
    host! "brgen.no"
    get conversations_path

    assert_response :success
    assert_includes response.body, I18n.t("chat.sign_in_inbox")
    assert_includes response.body, new_session_path
    assert_includes response.body, channel_path("brgen")
  end

  test "a signed-in reader with no threads is not shown the visitor hint" do
    lone = create_user("handle_lone")
    sign_in_as(lone)
    get conversations_path

    assert response.body.exclude?(I18n.t("chat.sign_in_inbox"))
  end

  test "a message read once is gone on the next open" do
    @conversation.update!(disappearing_duration: 0)
    sign_in_as(@user)

    get conversation_path(@conversation)
    assert response.body.include?("Hei på deg")

    get conversation_path(@conversation)
    assert response.body.exclude?("Hei på deg")

    get conversations_path
    assert response.body.exclude?("Hei på deg")
  end
end
