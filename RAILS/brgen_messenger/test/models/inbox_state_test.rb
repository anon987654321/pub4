# frozen_string_literal: true

require "test_helper"

# What the badge, the list and the sender's state say about a thread. Each case
# is a line the reader or the sender could see wrongly before.
class InboxStateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = create_user("inbox_me")
    @friend = create_user("inbox_friend")
    @conversation = Conversation.find_or_create_direct(@me, @friend)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def say(sender, content = "Hei")
    @conversation.messages.create!(sender: sender, content: content, message_type: "text")
  end

  def membership(user) = ConversationParticipant.find_by!(conversation: @conversation, user: user)

  test "the reader's own messages are not unread to them" do
    say(@me)
    say(@me)

    assert_equal 0, Conversation.unread_total_for(@me)
    assert_equal 0, @conversation.unread_count_for(@me)
    assert_equal 2, Conversation.unread_total_for(@friend)
  end

  test "an unsent message does not count as unread" do
    sent = say(@friend)
    say(@friend)
    sent.unsend!

    assert_equal 1, Conversation.unread_total_for(@me)
  end

  test "muting a thread takes it out of the badge and nothing else" do
    say(@friend)
    membership(@me).update!(muted_at: Time.current)

    assert_equal 0, Conversation.unread_total_for(@me)
    assert_equal 1, Conversation.unread_counts_for(@me)[@conversation.id]
  end

  test "mute is the muter's alone" do
    say(@me)
    membership(@me).update!(muted_at: Time.current)

    assert_equal 1, Conversation.unread_total_for(@friend)
  end

  test "a new message brings an archived thread back for the recipient only" do
    membership(@me).update!(archived_at: Time.current)
    membership(@friend).update!(archived_at: Time.current)

    say(@friend)

    assert_not_predicate membership(@me).reload, :archived?
    assert_predicate membership(@friend).reload, :archived?
  end

  test "in_inbox and in_archive split the viewer's own list" do
    other = Conversation.find_or_create_direct(@me, create_user("inbox_other"))
    membership(@me).update!(archived_at: Time.current)

    assert_equal [ other.id ], Conversation.for_user(@me).in_inbox.pluck(:id)
    assert_equal [ @conversation.id ], Conversation.for_user(@me).in_archive.pluck(:id)
  end

  test "the sender's state is sent until another person reads, then read" do
    message = say(@me)
    assert_equal [ :sent, 0 ], message.reload.delivery_state

    @conversation.mark_read_for!(@friend)
    assert_equal [ :read, 1 ], message.reload.delivery_state
  end

  test "opening your own thread does not read your own message for you" do
    message = say(@me)
    @conversation.mark_read_for!(@me)

    assert_equal [ :sent, 0 ], message.reload.delivery_state
    assert_equal 0, MessageReceipt.where(message: message, user: @me).count
  end

  test "a group says how many have read" do
    third = create_user("inbox_third")
    group = Conversation.create_group!(creator: @me, name: "Tur", users: [ @friend, third ])
    message = group.messages.create!(sender: @me, content: "Klar?", message_type: "text")

    group.mark_read_for!(@friend)
    group.mark_read_for!(third)

    assert_equal [ :read, 2 ], message.reload.delivery_state
  end

  test "reading broadcasts the new state into the sender's line" do
    message = say(@me)

    assert_enqueued_jobs 1, only: Turbo::Streams::ActionBroadcastJob do
      @conversation.mark_read_for!(@friend)
    end
    assert_predicate message.reload.message_receipts.find_by(user: @friend), :read?
  end
end
