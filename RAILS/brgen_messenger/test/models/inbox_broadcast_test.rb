# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# The inbox list, the rooms rail and the Messenger badge changed only on a
# reload. Each reader now gets their own row and count over their own stream.
class InboxBroadcastTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = create_user("live_inbox_me")
    @friend = create_user("live_inbox_friend")
    @conversation = Conversation.find_or_create_direct(@me, @friend)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def inbox_of(user) = [ user, :inbox ]

  def say(sender, content = "Hei")
    @conversation.messages.create!(sender:, content:, message_type: "text")
  end

  test "a new message moves the thread to the top of the recipient's inbox and lights their badge" do
    say(@friend, "Kino i kveld?")
    streams = capture_turbo_stream_broadcasts(inbox_of(@me)) { perform_enqueued_jobs(only: InboxBroadcastJob) }

    moved = streams.select { |stream| stream["action"] == "prepend" }
    assert_equal %w[inbox_conversations rail_conversations], moved.map { |stream| stream["target"] }
    assert_includes moved.first.to_html, "Kino i kveld?"
    assert_includes moved.first.to_html, @friend.display_name, "the row is named as the recipient sees it"
    badge = streams.find { |stream| stream["target"] == "messenger_unread_badge" }
    assert_includes badge.to_html, ">1</sup>"
  end

  test "opening the thread clears the reader's own count, and only theirs is redrawn" do
    say(@friend)
    perform_enqueued_jobs(only: InboxBroadcastJob)

    assert_enqueued_with(job: InboxBroadcastJob, args: [ @conversation.id, [ @me.id ] ]) do
      @conversation.mark_read_for!(@me)
    end
    streams = capture_turbo_stream_broadcasts(inbox_of(@me)) { perform_enqueued_jobs(only: InboxBroadcastJob) }

    assert_equal "replace", streams.first["action"]
    badge = streams.find { |stream| stream["target"] == "messenger_unread_badge" }
    refute_includes badge.to_html, "<sup"
  end

  test "a photo with no words previews as a photo, and an unsent line is not the preview" do
    photo = @conversation.messages.build(sender: @friend, content: "", message_type: "text")
    photo.attachment.attach(io: StringIO.new("GIF89a"), filename: "kart.gif", content_type: "image/gif")
    photo.save!
    regret = say(@friend, "Feil rom")
    regret.unsend!
    streams = capture_turbo_stream_broadcasts(inbox_of(@me)) { perform_enqueued_jobs(only: InboxBroadcastJob) }

    row_id = ActionView::RecordIdentifier.dom_id(@conversation, :inbox)
    row = streams.reverse.find { |stream| stream["target"] == row_id }
    assert_includes row.to_html, I18n.t("messages.preview_photo", locale: :nb)
    assert_equal photo, Conversation.last_messages_for([ @conversation.id ])[@conversation.id]
  end

  test "a public channel has no inbox row" do
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    channel.join!(@me)
    channel.join!(@friend)
    channel.messages.create!(sender: @friend, content: "Hei alle", message_type: "text")

    streams = capture_turbo_stream_broadcasts(inbox_of(@me)) { perform_enqueued_jobs(only: InboxBroadcastJob) }
    assert_empty streams
  end

  test "the tab bar's Messages badge is redrawn too, under its own id, carrying the title count" do
    say(@friend, "Ses?")
    streams = capture_turbo_stream_broadcasts(inbox_of(@me)) { perform_enqueued_jobs(only: InboxBroadcastJob) }

    tab = streams.find { |stream| stream["target"] == "messenger_unread_badge_tab" }
    assert tab, "no redraw of the tab bar's badge"
    assert_includes tab.to_html, ">1</sup>"
    span = tab.at_css("template span#messenger_unread_badge_tab")
    assert_equal "unread-title", span["data-controller"]
    assert_equal "1", span["data-unread-title-count-value"]
    swiper = streams.find { |stream| stream["target"] == "messenger_unread_badge" }
    assert_nil swiper.at_css("template [data-controller]"), "only one copy keeps the title"
  end
end
