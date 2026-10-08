# frozen_string_literal: true

require "test_helper"

class Tv::StreamChatTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @viewer = User.strict_loading(false).create!(
      email_address: "tv_chatter@brgen.no", password: "password123", city: @city
    )
    @stream = Tv::LiveStream.create!(user: @viewer, title: "Direkte fra Torget")
  end

  test "a chat line needs a message of at most 1000 characters" do
    blank = Tv::StreamChat.new(live_stream: @stream, user: @viewer, message: "")
    long = Tv::StreamChat.new(live_stream: @stream, user: @viewer, message: "x" * 1_001)

    assert_not blank.valid?
    assert blank.errors.added?(:message, :blank)
    assert_not long.valid?
    assert long.errors.added?(:message, :too_long, count: 1_000)
  end

  test "chronological reads the chat in the order it was said" do
    later = say("Hei fra Bryggen", at: 1.minute.ago)
    earlier = say("Første!", at: 5.minutes.ago)

    assert_equal [ earlier.id, later.id ], Tv::StreamChat.where(live_stream_id: @stream.id).chronological.ids
  end

  test "a new line reaches everyone watching the stream" do
    assert_broadcasts("tv:live_stream:#{@stream.id}:entries", 1) do
      say("Heia")
    end
  end

  private

  def say(message, at: Time.current)
    Tv::StreamChat.create!(live_stream: @stream, user: @viewer, message: message, created_at: at)
  end
end
