# frozen_string_literal: true

require "test_helper"

class Tv::VideoNoteTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @viewer = User.strict_loading(false).create!(
      email_address: "tv_noter@brgen.no", password: "password123", city: @city
    )
    @video = ActsAsTenant.with_tenant(@city) do
      channel = Tv::Channel.create!(user: @viewer, name: "Notater #{SecureRandom.hex(2)}")
      Tv::Video.create!(channel: channel, user: @viewer, title: "Klipp med notater", status: "published",
                        published_at: Time.current, duration_seconds: 90)
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a note needs a body of at most 2000 characters" do
    blank = Tv::VideoNote.new(video: @video, user: @viewer, body: "")
    long = Tv::VideoNote.new(video: @video, user: @viewer, body: "x" * 2_001)

    assert_not blank.valid?
    assert blank.errors.added?(:body, :blank)
    assert_not long.valid?
    assert long.errors.added?(:body, :too_long, count: 2_000)
  end

  test "a timestamp is optional and never before the clip starts" do
    early = Tv::VideoNote.new(video: @video, user: @viewer, body: "Før start", timestamp: -1)

    assert_not early.valid?
    assert early.errors.added?(:timestamp, :greater_than_or_equal_to, value: -1, count: 0)
    assert Tv::VideoNote.new(video: @video, user: @viewer, body: "Uten tid").valid?
    assert Tv::VideoNote.new(video: @video, user: @viewer, body: "Ved start", timestamp: 0).valid?
  end

  test "chronological follows the clip, recent follows the writing" do
    late_in_clip = note("Slutten", timestamp: 80, at: 5.minutes.ago)
    early_in_clip = note("Starten", timestamp: 10, at: 1.minute.ago)
    notes = Tv::VideoNote.where(video_id: @video.id)

    assert_equal [ early_in_clip.id, late_in_clip.id ], notes.chronological.ids
    assert_equal [ early_in_clip.id, late_in_clip.id ], notes.recent.ids
    assert_equal [ late_in_clip.id, early_in_clip.id ], notes.chronological.reverse_order.ids
  end

  test "a new note reaches everyone watching the clip" do
    assert_broadcasts("tv:video:#{@video.id}:notes", 1) do
      note("Se her")
    end
  end

  private

  def note(body, timestamp: nil, at: Time.current)
    Tv::VideoNote.create!(video: @video, user: @viewer, body: body, timestamp: timestamp, created_at: at)
  end
end
