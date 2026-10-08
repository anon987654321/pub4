# frozen_string_literal: true

require "test_helper"

class Playlist::TimestampedCommentTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "ts_comment@brgen.no",
                                               password: "password123", city: @city)
    @track = Playlist::Track.create!(title: "Kommentert", user: @user)
  end

  test "a comment needs a body, bounded, and a moment that is not before the start" do
    blank = Playlist::TimestampedComment.new(track: @track, user: @user, body: "", timestamp_seconds: -1)
    long = Playlist::TimestampedComment.new(track: @track, user: @user, body: "x" * 2_001)

    assert_not blank.valid?
    assert blank.errors.added?(:body, :blank)
    assert blank.errors.added?(:timestamp_seconds, :greater_than_or_equal_to, value: -1, count: 0)
    assert_not long.valid?
    assert long.errors.added?(:body, :too_long, count: 2_000)
  end

  test "a comment on the whole track carries no moment" do
    assert Playlist::TimestampedComment.new(track: @track, user: @user, body: "Fin låt").valid?
  end

  test "chronological follows the track's timeline, not the order comments were written" do
    chorus = comment("Refreng", at_second: 90)
    intro = comment("Intro", at_second: 5)

    timeline = Playlist::TimestampedComment.where(track_id: @track.id).chronological.ids
    assert_equal [ intro.id, chorus.id ], timeline
  end

  private

  def comment(body, at_second:)
    Playlist::TimestampedComment.create!(track: @track, user: @user, body: body, timestamp_seconds: at_second)
  end
end
