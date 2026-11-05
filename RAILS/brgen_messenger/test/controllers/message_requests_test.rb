# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A DM from someone the recipient has never talked to and does not follow is a
# message request: it waits in Requests, lights no badge, pushes nothing and
# tells the sender nothing until the recipient accepts it.
class MessageRequestsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @stranger = create_user("req_stranger")
    @recipient = create_user("req_recipient")
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

  def open_thread_with(user)
    post user_conversations_path(user)
    Conversation.direct_between(@stranger, user)
  end

  def membership(conversation, user)
    ConversationParticipant.find_by!(conversation:, user:)
  end

  test "a stranger's first message waits in Requests, silent and unread" do
    sign_in_as(@stranger)
    conversation = open_thread_with(@recipient)
    assert membership(conversation, @recipient).request?
    refute membership(conversation, @stranger).request?, "the sender's side is accepted"

    pushed = []
    Shared::Pushable.stub(:push_to, ->(user, **) { pushed << user }) do
      post conversation_messages_path(conversation), params: { message: { content: "Hei, selger du sykkelen?" } }
    end
    assert_empty pushed, "a request pushes nothing"
    assert_equal 0, Conversation.unread_total_for(@recipient), "and lights no badge"

    sign_in_as(@recipient)
    get conversations_path
    refute_includes response.body, ActionView::RecordIdentifier.dom_id(conversation, :inbox)
    assert_includes response.body, conversations_path(requests: 1)

    get conversations_path(requests: 1)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(conversation, :inbox)

    get conversation_path(conversation)
    assert_includes response.body, conversation_request_path(conversation)
    refute MessageReceipt.where(user: @recipient).read.exists?, "opening a request is not reading it"
  end

  test "accepting moves the thread to the inbox; declining takes the reader out of it" do
    sign_in_as(@stranger)
    conversation = open_thread_with(@recipient)

    sign_in_as(@recipient)
    post conversation_request_path(conversation)
    assert_redirected_to conversation_path(conversation)
    refute membership(conversation, @recipient).request?

    other = create_user("req_other")
    sign_in_as(other)
    post user_conversations_path(@recipient)
    second = Conversation.direct_between(other, @recipient)

    sign_in_as(@recipient)
    delete conversation_request_path(second)
    assert_nil ConversationParticipant.find_by(conversation: second, user: @recipient)
    get conversation_path(second)
    assert_response :not_found
  end

  test "nobody accepts a request on someone else's behalf" do
    sign_in_as(@stranger)
    conversation = open_thread_with(@recipient)

    post conversation_request_path(conversation)
    assert_response :not_found
    assert membership(conversation, @recipient).request?
  end

  test "answering a request accepts it" do
    sign_in_as(@stranger)
    conversation = open_thread_with(@recipient)

    sign_in_as(@recipient)
    post conversation_messages_path(conversation), params: { message: { content: "Ja, 500 kr" } }
    refute membership(conversation, @recipient).request?
  end

  test "someone the recipient follows, or has written to before, lands in the inbox" do
    Follow.create!(follower: @recipient, followed: @stranger)
    sign_in_as(@stranger)
    refute membership(open_thread_with(@recipient), @recipient).request?

    friend = create_user("req_friend")
    group = Conversation.create_group!(creator: friend, name: "Turlag", users: [ @recipient ])
    group.messages.create!(sender: @recipient, content: "Jeg blir med", message_type: "text")
    assert Conversation.known_to?(@recipient, friend)
    refute Conversation.known_to?(friend, @stranger)
  end

  test "a dating match, an order or any other door opens accepted" do
    conversation = Conversation.find_or_create_direct(@stranger, @recipient)
    refute membership(conversation, @recipient).request?
  end

  test "a guest's conversations are always requests, a few an hour" do
    targets = Array.new(6) { |i| create_user("req_target_#{i}") }
    host! "brgen.no"
    get conversations_path

    targets.each { |target| post user_conversations_path(target) }

    assert_equal I18n.t("flash.messages_rate_limited"), flash[:alert], "the sixth start in an hour is refused"
    assert_equal 5, ConversationParticipant.requests.where(user_id: targets.map(&:id)).count
    assert_equal 0, ConversationParticipant.accepted.where(user_id: targets.map(&:id)).count
  end

  test "report and block declines the request, reports what the sender wrote and blocks them" do
    sign_in_as(@stranger)
    conversation = open_thread_with(@recipient)
    spam = conversation.messages.create!(sender: @stranger, content: "Billig Rolex, klikk her", message_type: "text")

    sign_in_as(@recipient)
    get conversation_path(conversation)
    assert_select "form[action=?] button", conversation_request_path(conversation, report: 1),
                  text: I18n.t("messages.request_report_block")

    assert_enqueued_with(job: ModerationReportNotificationJob) do
      delete conversation_request_path(conversation, report: 1)
    end
    assert_redirected_to conversations_path(requests: 1)
    assert_equal I18n.t("flash.message_request_reported"), flash[:notice]
    assert_nil ConversationParticipant.find_by(conversation:, user: @recipient)
    report = ModerationReport.find_by!(user: @recipient)
    assert_equal [ "Message", spam.id ], [ report.reportable_type, report.reportable_id ]
    assert @recipient.reload.blocking?(@stranger)
  end
end
