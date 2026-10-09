# frozen_string_literal: true

require "test_helper"

# View once: a message goes the next time the thread is opened after everyone it
# was sent to has read it. The promise is about words and attachments, not about
# screenshots, which the app cannot see.
class ViewOnceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = create_user("once_me")
    @friend = create_user("once_friend")
    @conversation = Conversation.find_or_create_direct(@me, @friend)
    @conversation.update!(disappearing_duration: Conversation::DISAPPEARING_OPTIONS.fetch("after_read"))
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def say(sender, content = "Bare en gang")
    @conversation.messages.create!(sender: sender, content: content, message_type: "text")
  end

  test "the option exists and is its own mode, not a timer" do
    assert_predicate @conversation, :view_once?
    assert_predicate @conversation, :ephemeral?
    assert_not_predicate @conversation, :disappearing_messages?
  end

  test "other durations are not view once" do
    @conversation.update!(disappearing_duration: 3600)
    assert_not_predicate @conversation, :view_once?
    assert_predicate @conversation, :ephemeral?

    @conversation.update!(disappearing_duration: nil)
    assert_not_predicate @conversation, :ephemeral?
  end

  test "an unread message stays" do
    message = say(@me)
    @conversation.expire_read_messages!

    assert_not_predicate message.reload, :deleted?
  end

  test "a message goes on the visit after it was read" do
    message = say(@me)
    @conversation.mark_read_for!(@friend)

    @conversation.expire_read_messages!

    assert_predicate message.reload, :deleted?
    assert_equal "", message.content
  end

  test "in a group it stays until every person has read it" do
    third = create_user("once_third")
    group = Conversation.create_group!(creator: @me, name: "Tur", users: [ @friend, third ])
    group.update!(disappearing_duration: 0)
    message = group.messages.create!(sender: @me, content: "Alle", message_type: "text")

    group.mark_read_for!(@friend)
    group.expire_read_messages!
    assert_not_predicate message.reload, :deleted?

    group.mark_read_for!(third)
    group.expire_read_messages!
    assert_predicate message.reload, :deleted?
  end

  test "a bot is not waited for" do
    master = ChannelBot.bot_for("master")
    @conversation.join!(master)
    message = say(@me)
    @conversation.mark_read_for!(@friend)

    @conversation.expire_read_messages!

    assert_predicate message.reload, :deleted?
  end

  test "an unsent-and-expired message is out of search and forwarding" do
    message = say(@me)
    @conversation.mark_read_for!(@friend)
    @conversation.expire_read_messages!

    assert_not_predicate message.reload, :forwardable?
    assert_empty Message.visible.unexpired.where(id: message.id)
  end

  test "a conversation that is not view once expires nothing" do
    @conversation.update!(disappearing_duration: nil)
    message = say(@me)
    @conversation.mark_read_for!(@friend)

    @conversation.expire_read_messages!

    assert_not_predicate message.reload, :deleted?
  end

  test "view once schedules no timer" do
    assert_no_enqueued_jobs only: MessageExpirationJob do
      say(@me)
    end
  end
end
