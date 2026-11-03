# frozen_string_literal: true

require "test_helper"

# Every channel built on ApplicationCable::Channel acts for a user, so a
# connection with nobody behind it is refused all of them.
class AnonymousChannelTest < ActionCable::Channel::TestCase
  class ProbeChannel < ApplicationCable::Channel
    def subscribed = stream_from("probe")
  end

  tests ProbeChannel

  test "nobody is refused" do
    stub_connection(current_user: nil)
    subscribe

    assert subscription.rejected?
  end

  test "a reader is served" do
    stub_connection(current_user: User.new)
    subscribe

    assert subscription.confirmed?
  end
end
