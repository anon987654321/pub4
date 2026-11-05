# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# The unread count beside Varsler follows the reader's notifications live, on
# their own stream: up when one arrives, down when one is read or dismissed.
class NotificationUnreadBadgeTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @reader = User.strict_loading(false).create!(email_address: "badge-reader@brgen.no", password: "password123")
    @stream = Notification.unread_badge_stream(@reader)
  end

  def badge_after(&)
    replace = capture_turbo_stream_broadcasts(@stream, &).find { |stream| stream["action"] == "replace" }
    assert replace, "no badge redraw"
    assert_equal "notifications-unread-badge", replace["target"]
    replace.at_css("template sup")&.text.to_s
  end

  test "a new notification raises the count" do
    assert_equal "1", badge_after { Notification.create!(user: @reader, kind: "follow") }
    assert_equal "2", badge_after { Notification.create!(user: @reader, kind: "like") }
  end

  test "reading one lowers it and reading the last empties it" do
    first = Notification.create!(user: @reader, kind: "follow")
    Notification.create!(user: @reader, kind: "like")

    assert_equal "1", badge_after { first.mark_as_read! }
    assert_equal "", badge_after { Notification.where(user: @reader).unread.find_each(&:mark_as_read!) }
  end

  test "dismissing an unread one lowers it" do
    note = Notification.create!(user: @reader, kind: "follow")

    assert_equal "", badge_after { note.destroy! }
  end

  test "an edit that is not a read leaves the stream quiet" do
    note = Notification.create!(user: @reader, kind: "follow")

    streams = capture_turbo_stream_broadcasts(@stream) { note.update!(title: "Ny tittel") }
    assert_empty streams
  end

  test "the More button's copy of the badge is redrawn as well" do
    targets = capture_turbo_stream_broadcasts(@stream) { Notification.create!(user: @reader, kind: "follow") }
              .map { |stream| [ stream["target"], stream.at_css("template sup")&.text ] }
    assert_equal [ [ "notifications-unread-badge", "1" ], [ "notifications-unread-badge-tab", "1" ] ], targets
  end
end
