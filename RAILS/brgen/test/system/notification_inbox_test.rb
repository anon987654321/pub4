# frozen_string_literal: true

require "application_system_test_case"

# The notification inbox in a browser: the swipe that dismisses a row, and the
# Undo it offers before anything is deleted.
class NotificationInboxTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @reader = User.strict_loading(false).create!(
      email_address: "inbox_reader_#{SecureRandom.hex(2)}@brgen.no", password: "password123",
      username: "inbox_reader_#{SecureRandom.hex(2)}", guest: false, city: @city
    )
  end

  test "a swiped row waits behind Undo, and is deleted only once the reader moves on" do
    # Two kinds that are never folded into one card.
    first = Notification.create!(user: @reader, kind: "mention", title: "Kari nevnte deg")
    second = Notification.create!(user: @reader, kind: "reply", title: "Ola svarte deg")
    sign_in_on_city(@reader)
    visit_city(nil, "/notifications")
    decline_optional_cookies if page.has_css?("#cookie-consent-banner", wait: 1)

    swipe_left(first)
    assert_no_selector "##{dom_id(first)}", wait: 5
    within(".notification-undo-toast") { click_button I18n.t("notifications.undo_dismiss") }
    assert_selector "##{dom_id(first)}", visible: true
    assert Notification.exists?(first.id), "Undo kept the notification"

    swipe_left(first)
    assert_selector ".notification-undo-toast", text: I18n.t("notifications.swiped_away")
    sleep 1
    assert Notification.exists?(first.id), "nothing is deleted while Undo is on offer"

    # Swiping the next row sends the first; the second now waits in its place.
    swipe_left(second)
    assert wait_until { !Notification.exists?(first.id) }, "the first row was not sent when the next one went"
    assert Notification.exists?(second.id)

    # Leaving the page sends the one still waiting.
    page.execute_script("Turbo.visit('/communities')")
    assert wait_until { !Notification.exists?(second.id) }, "leaving the page did not send the waiting row"
  end

  private

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

  # Pointer events from the row's middle to well past the dismiss threshold.
  def swipe_left(notification)
    page.execute_script(<<~JS, dom_id(notification))
      const row = document.getElementById(arguments[0])
      const box = row.getBoundingClientRect()
      const y = box.top + 10
      const fire = (type, x) => row.dispatchEvent(
        new PointerEvent(type, { bubbles: true, isPrimary: true, pointerId: 7, clientX: x, clientY: y })
      )
      fire("pointerdown", box.right - 10)
      fire("pointermove", box.right - 40)
      fire("pointermove", box.left + 10)
      fire("pointerup", box.left + 10)
    JS
  end
end
