# frozen_string_literal: true

require "test_helper"

# Stories had no conversation hook at all: a viewer could look and leave.
class StoryRepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = create_user("sr_author")
    @viewer = create_user("sr_viewer")
    ActsAsTenant.current_tenant = @city
    @story = Story.new(user: @author, caption: "Sol på Fløyen")
    attach_pixel!(@story.media, filename: "story.png")
    @story.save!
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a reply lands in the pair's own thread and says what it answers" do
    sign_in_as(@viewer)

    assert_difference -> { Message.count }, 1 do
      post story_replies_path(@story), params: { content: "Fin utsikt" }
    end
    message = Message.order(:created_at).last
    assert_equal @story.id, message.story_id
    assert_equal @viewer.id, message.sender_id
    conversation = Conversation.direct_between(@viewer, @author)
    assert_equal conversation.id, message.conversation_id
    assert_redirected_to conversation_path(conversation)
  end

  # The reply outlives the story: the sweep takes the photo, not the answer.
  test "the reply survives the story it answered" do
    sign_in_as(@viewer)
    post story_replies_path(@story), params: { content: "Fin utsikt" }
    message = Message.order(:created_at).last

    Story.find(@story.id).destroy
    assert_equal "Fin utsikt", message.reload.content
    assert_nil message.story_id
  end

  # A reply box that still works after the sweep is a promise broken quietly.
  test "an expired story takes no replies" do
    @story.update!(expires_at: 1.minute.ago)
    sign_in_as(@viewer)

    post story_replies_path(@story), params: { content: "For sent" }
    assert_response :not_found
  end

  test "the author has nobody to answer but themselves" do
    sign_in_as(@author)

    assert_no_difference -> { Message.count } do
      post story_replies_path(@story), params: { content: "Meg selv" }
    end
    assert_redirected_to stories_path
  end

  test "a block stops the reply in either direction" do
    @author.block!(@viewer)
    sign_in_as(@viewer)

    assert_no_difference -> { Message.count } do
      post story_replies_path(@story), params: { content: "Hei" }
    end
  end

  test "the story page carries the reply box for everyone but its author" do
    sign_in_as(@viewer)
    get story_path(@story)
    assert_includes response.body, story_replies_path(@story)

    sign_in_as(@author)
    get story_path(@story)
    assert_not_includes response.body, story_replies_path(@story)
  end
end
