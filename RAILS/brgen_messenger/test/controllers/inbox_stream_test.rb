# frozen_string_literal: true

require "test_helper"

# InboxBroadcastJob replaces these ids over the reader's own stream; a page
# without the subscription or the ids would receive nothing it can apply.
class InboxStreamTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @user = create_user("stream_user")
    @friend = create_user("stream_friend")
    @conversation = Conversation.find_or_create_direct(@user, @friend)
    Message.create!(conversation: @conversation, sender: @friend, content: "Hei", message_type: "text")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  test "the inbox page subscribes to the reader's own stream and carries the ids it updates" do
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    get conversations_path

    body = response.body
    assert_includes body, %(signed-stream-name="#{Turbo::StreamsChannel.signed_stream_name([ @user, :inbox ])}")
    %w[inbox_conversations rail_conversations messenger_unread_badge].each do |id|
      assert_includes body, %(id="#{id}")
    end
    %i[inbox rail].each do |prefix|
      assert_includes body, %(id="#{ActionView::RecordIdentifier.dom_id(@conversation, prefix)}")
    end
  end

  # Reading, muting and pinning are the reader's own, so only their inbox moves.
  test "muting a thread redraws the muter's row and nobody else's" do
    membership = ConversationParticipant.find_by!(conversation: @conversation, user: @user)

    assert_enqueued_with(job: InboxBroadcastJob, args: [ @conversation.id, [ @user.id ] ]) do
      membership.update!(muted_at: Time.current)
    end
  end
end
