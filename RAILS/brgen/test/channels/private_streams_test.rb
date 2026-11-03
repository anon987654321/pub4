# frozen_string_literal: true

require "test_helper"

# A signed stream name never expires, so it proves only that the app once
# rendered it. Membership of a private conversation is asked again at every
# subscribe; a person's inbox and notifications are theirs alone.
class PrivateStreamsTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = create_user("stream_owner")
    @member = create_user("stream_member")
    @outsider = create_user("stream_outsider")
    @group = Conversation.create_group!(creator: @owner, name: "Hyttetur", users: [ @member ])
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(email_address: "#{name}@brgen.no", password: "password123",
                                       username: name, city: @city)
  end

  test "a participant reads the conversation's stream" do
    assert_subscribed_as(@member, @group)
  end

  test "a removed member's still-valid name is refused" do
    name = Turbo::StreamsChannel.signed_stream_name(@group)
    ConversationParticipant.find_by!(conversation: @group, user: @member).destroy!

    stub_connection(current_user: @member)
    subscribe(signed_stream_name: name)
    assert subscription.rejected?
  end

  test "someone never in the conversation is refused" do
    assert_refused_as(@outsider, @group)
    assert_refused_as(@outsider, Conversation.find_or_create_direct(@owner, @member))
  end

  test "a public channel streams to the city as its page does" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    assert_subscribed_as(@outsider, channel)
  end

  test "an inbox and notifications are their owner's only" do
    assert_subscribed_as(@owner, [ @owner, :inbox ])
    assert_refused_as(@outsider, [ @owner, :inbox ])
    assert_refused_as(@outsider, [ @owner, :notifications ])
    assert_subscribed_as(@outsider, @owner)
  end

  private

  def assert_subscribed_as(user, streamable)
    stub_connection(current_user: user)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(streamable))

    assert subscription.confirmed?, "#{streamable.inspect} was refused"
  end

  def assert_refused_as(user, streamable)
    stub_connection(current_user: user)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(streamable))

    assert subscription.rejected?, "#{streamable.inspect} was allowed"
  end
end
