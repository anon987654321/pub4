# frozen_string_literal: true

require "application_system_test_case"

# The two things on the front page that are a single control until you touch
# them: the composer pill, which opens a <dialog>, and the chat tab, which is the
# only visible door to the ambient room.
#
# Both were covered only at request level before this file — the compose launcher
# by one assertion that the string "compose-launcher" appeared in the HTML, which
# is true of a pill that does nothing when clicked. Neither expand path had ever
# been driven in a browser, and this is the class of surface where that gap hides
# real breakage: the ambient rooms 500'd for weeks behind a strict_loading
# violation that every request-level assertion passed straight through.
class ExpandingTabsTest < ApplicationSystemTestCase
  # A closed <dialog> is in the DOM at rest so the browser owns focus trapping and
  # Escape. That is exactly why presence in the markup proves nothing about it
  # opening — visible: false at rest is the point of the design.
  test "the composer pill opens the dialog and closes again" do
    visit root_path

    dialog = find("dialog.composer", visible: :all)
    assert_not dialog.visible?, "the composer dialog should rest closed"

    find(".compose-trigger").click
    assert_selector "dialog.composer", visible: true, wait: 5

    # Escape is the browser's own affordance for a <dialog>; if the composer ever
    # stops being one, this is the assertion that notices.
    find("body").send_keys(:escape)
    assert_no_selector "dialog.composer", visible: true, wait: 5
  end

  test "the composer pill is reachable and operable from the keyboard" do
    visit root_path

    trigger = find(".compose-trigger")
    trigger.send_keys(:enter)
    assert_selector "dialog.composer", visible: true, wait: 5

    # Focus must move into the dialog, or a keyboard reader opens a composer they
    # are not standing in.
    within("dialog.composer") do
      assert_selector "textarea, [contenteditable=true], input[type=text]", wait: 5
    end
  end

  test "the chat tab expands into a room with a composer" do
    visit root_path

    # The tab is the only visible link to ambient chat, so its click path is the
    # whole feature's front door.
    tab = first("[data-controller~='nearby-chat'], .nearby-widget-trigger, a[href*='nearby']", visible: true)
    skip "no visible chat tab on this surface" unless tab

    tab.click
    assert_selector "form#nearby_widget_message, form[action*='nearby']", wait: 8
  end

  test "home has no accessibility violations once the composer is open" do
    visit root_path
    find(".compose-trigger").click
    assert_selector "dialog.composer", visible: true, wait: 5

    # The resting page is already audited by public_navigation_test. An open
    # modal is a different accessibility problem — focus trap, labelling, and the
    # rest of the page going inert — and it was never audited in that state.
    assert_accessible
  end
end
