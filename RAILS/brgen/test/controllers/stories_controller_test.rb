# frozen_string_literal: true

require "test_helper"

class StoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(
      email_address: "sc_author@brgen.no", password: "password123", username: "sc_author", guest: false
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "sc_viewer@brgen.no", password: "password123", username: "sc_viewer", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @story = build_story(@author)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def build_story(user, **attrs)
    s = Story.new({ user: user, caption: "Bryggen" }.merge(attrs))
    s.media.attach(ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-jpeg-bytes"), filename: "snap.jpg", content_type: "image/jpeg", identify: false
    ))
    s.save!
    s
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "the ring index renders for a guest" do
    host! "brgen.no"

    get stories_path
    assert_response :success
    assert_match @author.display_name, response.body
  end

  # The ring list asked "seen?" once per ring; it is one query for the page.
  test "the ring index reads seen state in one query however many rings" do
    others = 3.times.map do |i|
      User.strict_loading(false).create!(email_address: "sc_ring#{i}@brgen.no", password: "password123",
                                         username: "sc_ring#{i}", guest: false)
    end
    others.each { |user| build_story(user) }
    @story.view_by!(@viewer)
    sign_in_as(@viewer)

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] if payload[:sql].include?("story_views")
    end
    get stories_path
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_response :success
    assert_equal 1, queries.size, queries.join("\n")
    assert_select "li.story-ring--seen", 1
  end

  # The form takes video/*; asking a clip for an image variant raised, so a
  # video story could be posted and then neither opened nor listed.
  test "a video story plays in the viewer and lists without a thumbnail" do
    clip = Story.new(user: @author, caption: "Klipp")
    clip.media.attach(ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-mp4-bytes"), filename: "klipp.mp4", content_type: "video/mp4", identify: false
    ))
    clip.save!
    sign_in_as(@viewer)

    get story_path(clip)
    assert_response :success
    assert_select ".story-media video[controls][playsinline][muted][aria-label=?]", "Klipp"

    get stories_path
    assert_response :success
  end

  test "opening someone's story records one view" do
    sign_in_as(@viewer)

    assert_difference -> { StoryView.count }, 1 do
      get story_path(@story)
    end
    assert_response :success

    # Opening it again is not a second view.
    assert_no_difference -> { StoryView.count } do
      get story_path(@story)
    end
  end

  # Turbo prefetches a link on hover. A hover is not a view.
  test "a prefetch of someone's story records no view" do
    sign_in_as(@viewer)

    assert_no_difference -> { StoryView.count } do
      get story_path(@story), headers: { "X-Sec-Purpose" => "prefetch" }
    end
    assert_response :success
  end

  # An expired story is gone as far as every surface is concerned, whether or
  # not the sweep has run yet — otherwise the link keeps working while the job
  # is behind.
  test "an expired story is already unreachable" do
    sign_in_as(@viewer)
    @story.update_columns(expires_at: 1.minute.ago)

    get story_path(@story)
    assert_response :not_found
  end

  test "posting a story needs media" do
    sign_in_as(@author)

    assert_no_difference -> { Story.count } do
      post stories_path, params: { story: { caption: "uten bilde" } }
    end
    assert_response :unprocessable_entity
  end

  test "a guest cannot post a story" do
    host! "brgen.no"

    assert_no_difference -> { Story.count } do
      post stories_path, params: { story: { caption: "hei" } }
    end
  end

  # The viewer list is the author's alone; everyone else sees only the count.
  test "only the author sees who watched" do
    sign_in_as(@viewer)
    get story_path(@story)
    refute_match @viewer.display_name, response.body.split("story-caption").last.to_s

    sign_in_as(@author)
    get story_path(@story)
    assert_match @viewer.display_name, response.body
  end

  test "an author deletes their own story and nobody else's" do
    sign_in_as(@viewer)
    delete story_path(@story)
    assert_response :not_found

    sign_in_as(@author)
    assert_difference -> { Story.count }, -1 do
      delete story_path(@story)
    end
  end
end
