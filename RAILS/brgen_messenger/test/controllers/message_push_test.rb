# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A chat message is not a Notification row, so NativePushJob, which only ever
# fired from Notification, never sent one: a message reached web push and no
# phone. These pin the APNs half beside the web half, with the same filters.
class MessagePushTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @sender = create_user("push_sender")
    @reader = create_user("push_reader")
    @muted = create_user("push_muted")

    @group = Conversation.create_group!(creator: @sender, name: "Middag", users: [ @reader, @muted ])
    ConversationParticipant.find_by!(conversation: @group, user: @muted).update!(muted_at: Time.current)
    host! "brgen.no"
    post session_path, params: { email_address: @sender.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def native_pushes_for(params)
    sent = []
    Apns.stub(:configured?, true) do
      NativePushJob.stub(:perform_later, ->(**payload) { sent << payload }) do
        post conversation_messages_path(@group), params: { message: params }
      end
    end
    sent
  end

  test "a message reaches the reader's phone, not a muted member's, in the conversation's own thread" do
    sent = native_pushes_for(content: "Taco kl 18?", message_type: "text")

    assert_equal [ @reader.id ], sent.map { |payload| payload[:user_id] }
    assert_equal "Taco kl 18?", sent.first[:body]
    assert_equal @sender.display_name, sent.first[:title]
    assert_equal "brgen-conversation-#{@group.id}", sent.first[:thread]
    assert_equal "/conversations/#{@group.id}", sent.first[:path]
  end

  test "a photo says it is a photo on the lock screen" do
    photo = Rack::Test::UploadedFile.new(StringIO.new("GIF89a"), "image/gif", true, original_filename: "kart.gif")
    sent = native_pushes_for(content: "", message_type: "text", attachment: photo)

    assert_equal I18n.t("messages.preview_photo"), sent.first[:body]
  end

  test "the job sends the words to the reader's devices through APNs" do
    NativePushToken.create!(user: @reader, token: "ab" * 32)
    delivered = []
    Apns.stub(:configured?, true) do
      Apns.stub(:deliver, ->(tokens, message) { delivered << [ tokens.map(&:user_id), message ] }) do
        NativePushJob.perform_now(user_id: @reader.id, title: "Ola", body: "Hei", path: "/conversations/1",
                                  thread: "brgen-conversation-1")
      end
    end

    assert_equal [ [ [ @reader.id ], { title: "Ola", body: "Hei", path: "/conversations/1",
                                       thread: "brgen-conversation-1" } ] ], delivered
  end
end
