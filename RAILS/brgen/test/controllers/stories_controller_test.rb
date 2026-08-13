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
