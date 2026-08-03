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

  test "join! only ever raises a role, never demotes" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    op_bot = User.find_by!(username: "master", bot: true)
    channel.join!(op_bot, role: "member") # re-join lower must not demote
    assert_equal "op", channel.conversation_participants.find_by!(user: op_bot).role
  end
end
