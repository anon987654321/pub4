# frozen_string_literal: true

require "test_helper"

# Starting a conversation used to require typing someone's exact username into a
# blank field on the inbox, which is the one thing you do not know about someone
# you have just met. conversations#new searches people instead, and User.messageable
# decides who may appear there.
#
# "Everyone" is the obvious implementation of that scope and the wrong one, so
# each exclusion is pinned separately with its reason rather than as one list.
class MessageableScopeTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = create_user("me")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(handle, **attrs)
    User.create!(email_address: "#{handle}-#{SecureRandom.hex(4)}@brgen.no",
                 password: "password123", password_confirmation: "password123",
                 username: "#{handle}_#{SecureRandom.hex(3)}", city: @city, **attrs)
  end

  test "an ordinary account is messageable" do
    other = create_user("other")

    assert_includes User.messageable.pluck(:id), other.id
  end

  # A guest has no stable identity to hold a thread open across sessions, so a
  # conversation started with one is a conversation that loses its other half.
  test "a guest is not messageable" do
    guest = create_user("guest", guest: true)

    refute_includes User.messageable.pluck(:id), guest.id
  end

  # Bots are addressed in the channel they serve. A private thread with one is a
  # dead end: nothing reads it.
  test "a bot is not messageable" do
    bot = create_user("bot", bot: true)

    refute_includes User.messageable.pluck(:id), bot.id
  end

  test "a deleted account is not messageable" do
    gone = create_user("gone")
    gone.update_column(:deleted_at, Time.current)

    refute_includes User.messageable.pluck(:id), gone.id
  end

  # Someone on the way out should not collect new threads they will never read.
  test "an account scheduled for deletion is not messageable" do
    leaving = create_user("leaving")
    leaving.update_column(:deletion_scheduled_at, 1.day.from_now)

    refute_includes User.messageable.pluck(:id), leaving.id
  end

  # The picker's button posts to conversations#create, which calls this. Without
  # it a second click on the same person would open a second empty thread beside
  # the one that already holds their messages.
  test "messaging the same person twice reuses the conversation" do
    other = create_user("other")

    first = Conversation.find_or_create_direct(@me, other)
    assert_no_difference -> { Conversation.count } do
      assert_equal first.id, Conversation.find_or_create_direct(@me, other).id
    end
  end
end
