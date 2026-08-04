# frozen_string_literal: true

require "test_helper"

# IRC modes + populate-on-open: opening a channel seats the persona bot as an op
# and echo as a voice, seeds a few opening lines so the room reads alive, and the
# roster ranks ops before voices.
class ChannelRosterTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
  end

  test "opening a channel seats an op and a voice and seeds opening lines" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    roles = channel.conversation_participants.includes(:user)
                   .each_with_object({}) { |m, h| h[m.user.username] = m.role }
    assert_equal "op", roles["master"], "the persona host is the op"
    assert_equal "voice", roles["echo"], "echo is a voice"
    assert_operator channel.messages.count, :>=, 2, "the room must read alive on open"
  end

  test "by_rank puts ops before voices" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    assert_equal "op", channel.conversation_participants.by_rank.first.role
  end

  # The failure this pins is invisible from the outside: chrome, roster and topic
  # all render correctly on a room with nothing in it. Observed on production
  # #brgen — @master and +echo in the roster, topic line set, zero messages.
  #
  # welcome! runs once inside create_channel!, and its posts carry the room's own
  # CHANNEL_TTL like every other channel message, so six hours after creation the
  # room is empty for good unless a human speaks into a page giving them no
  # reason to.
  test "a channel whose opening lines have expired repopulates when reopened" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    assert_operator channel.messages.unexpired.count, :>, 0, "fixture precondition"

    # Age every message past its expiry the way six hours of wall clock would.
    channel.messages.update_all(expires_at: 1.minute.ago)
    assert_equal 0, channel.messages.unexpired.count, "the room is now empty, as production was"

    reopened = Conversation.find_or_create_channel("brgen", city: @city)
    assert_equal channel.id, reopened.id, "reopening must not create a second room"
    assert_operator reopened.messages.unexpired.count, :>, 0,
                    "an empty room must seed opening lines again on open"
  end

  test "reopening a room that still has messages does not re-seed" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    before = channel.messages.unexpired.count

    Conversation.find_or_create_channel("brgen", city: @city)

    assert_equal before, channel.messages.unexpired.count,
                 "a live room must not accumulate a fresh welcome on every open"
  end

  test "join! only ever raises a role, never demotes" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    op_bot = User.find_by!(username: "master", bot: true)
    channel.join!(op_bot, role: "member") # re-join lower must not demote
    assert_equal "op", channel.conversation_participants.find_by!(user: op_bot).role
  end
end
