# frozen_string_literal: true

require "test_helper"

# messages.duration_seconds, Message#voice? and the thread's <audio> element all
# shipped with no recorder anywhere in the tree. These pin the server half the
# recorder posts to.
class VoiceMessageTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @sender = create_user("voice_sender")
    @friend = create_user("voice_friend")
    ActsAsTenant.current_tenant = @city
    @conversation = Conversation.find_or_create_direct(@sender, @friend)
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

  def audio_upload
    Rack::Test::UploadedFile.new(StringIO.new("RIFF....WAVEfmt "), "audio/webm", true, original_filename: "voice-3s.webm")
  end

  # A voice note has no words in it by definition; requiring some is how a
  # client ends up sending a space.
  test "an attachment is a message without a body" do
    sign_in_as(@sender)

    assert_difference -> { @conversation.messages.count }, 1 do
      post conversation_messages_path(@conversation),
           params: { message: { message_type: "audio", duration_seconds: 3, attachment: audio_upload } }
    end
    message = @conversation.messages.order(:created_at).last
    assert_predicate message, :voice?
    assert_equal 3, message.duration_seconds
    assert message.attachment.attached?
  end

  test "a text message with no body is still refused" do
    sign_in_as(@sender)

    assert_no_difference -> { @conversation.messages.count } do
      post conversation_messages_path(@conversation), params: { message: { content: "", message_type: "text" } }
    end
  end

  test "the composer carries the recorder" do
    sign_in_as(@sender)

    get conversation_path(@conversation)
    assert_includes response.body, "voice-recorder"
    assert_includes response.body, "data-voice-recorder-target=\"file\""
  end
end
