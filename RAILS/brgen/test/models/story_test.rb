# frozen_string_literal: true

require "test_helper"

# brgen already had ephemerality, but only inside DMs — Conversation's
# disappearing_duration and Message#expires_at. There was no 24-hour story, no
# camera-first capture, and nothing on a public surface that goes away by itself.
class StoryTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(
      email_address: "st_author@brgen.no", password: "password123", username: "st_author", city: @city
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "st_viewer@brgen.no", password: "password123", username: "st_viewer", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def image
    # identify: false because Active Storage otherwise shells out to identify
    # the content type of every blob, which cost about 0.8s per attachment and
    # took the whole suite from 24s to 95s.
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-jpeg-bytes"), filename: "snap.jpg", content_type: "image/jpeg", identify: false
    )
  end

  def story(user: @author, **attrs)
    s = Story.new({ user: user, caption: "Regn igjen" }.merge(attrs))
    s.media.attach(image)
    s.save!
    s
  end

  test "a story sets its own 24-hour expiry" do
    s = story

    assert_in_delta Story::LIFETIME.from_now.to_i, s.expires_at.to_i, 5
    refute s.expired?
    assert_operator s.expires_in, :>, 0
  end

  # The lifetime lives on the row, so the alive scope, the countdown label and
  # the sweep all read one column rather than each re-deriving 24 hours.
  test "alive hides an expired story before the sweep has run" do
    fresh = story
    stale = story
    stale.update_columns(expires_at: 1.minute.ago)

    ids = Story.alive.map(&:id)
    assert_includes ids, fresh.id
    refute_includes ids, stale.id
    assert stale.reload.expired?
  end

  test "a story with no media is refused" do
    s = Story.new(user: @author, caption: "tom")

    refute s.valid?
    assert s.errors.of_kind?(:media, :blank)
  end

  test "seen is a set — viewing twice counts once" do
    s = story

    assert s.view_by!(@viewer)
    assert_equal 1, s.reload.views_count

    refute s.view_by!(@viewer), "a second open is not a second view"
    assert_equal 1, s.reload.views_count
    assert s.seen_by?(@viewer)
  end

  test "the author viewing their own story does not count" do
    s = story

    refute s.view_by!(@author)
    assert_equal 0, s.reload.views_count
  end

  test "the view count bumps updated_at so the cached ring changes" do
    s = story
    before = s.updated_at

    travel 1.second do
      s.view_by!(@viewer)
    end

    assert_operator s.reload.updated_at, :>, before
  end

  # Same coarsening as Post's Live layer: a story is often posted from where you
  # are standing, and exact GPS on a public surface is not collected by default.
  test "an attached area is inherited from the user and coarsened" do
    @author.update_columns(latitude: 60.391234, longitude: 5.322891)

    tagged = story(attach_area: true)
    assert_equal 60.39, tagged.latitude.to_f
    assert_equal 5.32, tagged.longitude.to_f

    untagged = story
    assert_nil untagged.latitude
  end

  test "attaching an area with no known position leaves it blank" do
    assert_nil @author.latitude, "guard: no position stored"

    assert_nil story(attach_area: true).latitude
  end

  # A story surface is a list of people, not a list of photos.
  test "rings group by author, newest first, with followed authors ahead" do
    other = User.strict_loading(false).create!(
      email_address: "st_other@brgen.no", password: "password123", username: "st_other", city: @city
    )
    story(user: other)
    older = story(user: @author)
    newer = story(user: @author)
    @viewer.follow!(@author)

    rings = Story.rings_for(@viewer)
    assert_equal @author.id, rings.first.first.user_id, "followed authors come first"
    assert_equal newer.id, rings.first.first.id, "newest first within a ring"
    assert_includes rings.first.map(&:id), older.id
  end

  test "the sweep destroys expired stories and their views" do
    stale = story
    stale.view_by!(@viewer)
    stale.update_columns(expires_at: 1.minute.ago)
    fresh = story

    assert_difference -> { StoryView.count }, -1 do
      assert_difference -> { Story.count }, -1 do
        ExpiredStoriesSweepJob.perform_now
      end
    end
    assert Story.exists?(fresh.id)
  end
end
