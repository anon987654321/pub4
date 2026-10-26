# frozen_string_literal: true

require "test_helper"

class MessageForwardTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = create_user("fwd_user")
    @friend = create_user("fwd_friend")
    @colleague = create_user("fwd_colleague")
    @stranger = create_user("fwd_stranger")
    ActsAsTenant.current_tenant = @city
    @source = Conversation.find_or_create_direct(@user, @friend)
    @target = Conversation.find_or_create_direct(@user, @colleague)
    @theirs = Conversation.find_or_create_direct(@friend, @stranger)
    @message = say(@source, @friend, "Møtet er flyttet til torsdag")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def say(conversation, sender, content)
    Message.create!(conversation: conversation, sender: sender, content: content, message_type: "text")
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "forwarding writes a copy into the target thread" do
    sign_in_as(@user)

    assert_difference -> { @target.messages.count }, 1 do
      post forward_conversation_message_path(@source, @message), params: { target_conversation_id: @target.id }
    end
    assert_redirected_to conversation_path(@target)

    copy = @target.messages.order(:created_at).last
    assert_equal @message.content, copy.content
    assert_equal @user.id, copy.sender_id
    assert_equal @message.id, copy.forwarded_from_id
  end

  # The copy is the forwarder's message in someone else's thread. Unsending the
  # original is a claim about the original thread only.
  test "unsending the original leaves the copy standing" do
    sign_in_as(@user)
    post forward_conversation_message_path(@source, @message), params: { target_conversation_id: @target.id }
    copy = @target.messages.order(:created_at).last

    @message.unsend!
    assert_equal "Møtet er flyttet til torsdag", copy.reload.content
    # Unsending is a soft delete, so the pointer home survives it. What breaks
    # the link is the source thread being destroyed outright.
    assert_equal @message.id, copy.forwarded_from_id

    @source.destroy
    assert_nil copy.reload.forwarded_from_id
  end

  test "a thread the reader is not in is neither source nor target" do
    sign_in_as(@user)
    theirs_message = say(@theirs, @stranger, "Hemmelig")

    post forward_conversation_message_path(@theirs, theirs_message), params: { target_conversation_id: @target.id }
    assert_response :not_found

    post forward_conversation_message_path(@source, @message), params: { target_conversation_id: @theirs.id }
    assert_response :not_found
  end

  test "an unsent message has nothing to forward" do
    sign_in_as(@user)
    @message.unsend!

    post forward_conversation_message_path(@source, @message), params: { target_conversation_id: @target.id }
    assert_response :not_found
  end

  # Reply, edit and unsend each had a route and a model method and no control on
  # any page, which is the same as not having them.
  test "the thread page carries the controls its backend has" do
    sign_in_as(@user)
    mine = say(@source, @user, "Jeg kommer")

    get conversation_path(@source)
    assert_response :success
    assert_includes response.body, conversation_path(@source, reply_to: @message.id)
    assert_includes response.body, conversation_path(@source, edit: mine.id)
    assert_includes response.body, forward_conversation_message_path(@source, @message)
  end

  test "a reply chosen by link is sent as a reply" do
    sign_in_as(@user)

    get conversation_path(@source, reply_to: @message.id)
    assert_includes response.body, "Svarer"

    post conversation_messages_path(@source), params: { message: { content: "Ja", message_type: "text", parent_id: @message.id } }
    assert_equal @message.id, @source.messages.order(:created_at).last.parent_id
  end

  test "a block on the target thread stops a forward into it" do
    Block.create!(blocker: @colleague, blocked: @user)
    sign_in_as(@user)

    assert_no_difference -> { @target.messages.count } do
      post forward_conversation_message_path(@source, @message), params: { target_conversation_id: @target.id }
    end
  end

  # The reply line draws the parent's sender and first words, so a parent from a
  # thread the sender is not in would read that thread by guessing ids.
  test "a reply cannot name a parent from another conversation" do
    private_line = say(@theirs, @stranger, "Koden til porten er 4417")
    sign_in_as(@user)

    assert_no_difference -> { @source.messages.count } do
      post conversation_messages_path(@source), params: { message: { content: "svar", parent_id: private_line.id } }
    end
    reply = @source.messages.build(sender: @user, content: "svar", parent_id: @message.id)
    reply.validate
    assert_empty reply.errors[:parent_id], "a parent in the same thread is still a reply"
  end
end
