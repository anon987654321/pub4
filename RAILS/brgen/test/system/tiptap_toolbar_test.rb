# frozen_string_literal: true

require "application_system_test_case"

# The formatting toolbar the composer, the post form and the comment form share
# was three loose buttons, each its own tab stop. It is a role=toolbar now:
# one tab stop, with the arrow keys, Home and End moving between its buttons.
class TiptapToolbarTest < ApplicationSystemTestCase
  def focused_label = evaluate_script("document.activeElement.getAttribute('aria-label')")

  test "the composer's toolbar is one tab stop the arrow keys move through" do
    visit root_path
    decline_optional_cookies if has_css?("#cookie-consent-banner", wait: 3)
    find("button.welcome-onboarding-close", wait: 5).click if has_css?("button.welcome-onboarding-close", wait: 3)
    find("button.compose-trigger").click
    # Opening the composer mounts the editor and carries the caret into it;
    # the toolbar is driven once that has happened.
    assert_selector "dialog.composer .tiptap_area[contenteditable=true]"

    toolbar = find("dialog.composer [role=toolbar][aria-label='#{I18n.t("tiptap.toolbar_label")}']")
    bold, italic, bullets = toolbar.all("button").map { _1["aria-label"] }
    assert_equal [ "0", "-1", "-1" ], toolbar.all("button").map { _1["tabindex"] }

    toolbar.find("button[aria-label='#{bold}']").send_keys(:arrow_right)
    assert_equal italic, focused_label
    page.send_keys(:end)
    assert_equal bullets, focused_label
    page.send_keys(:arrow_right)
    assert_equal bold, focused_label, "the arrows wrap"
    page.send_keys(:arrow_left, :home)
    assert_equal bold, focused_label
    assert_equal [ "0", "-1", "-1" ], toolbar.all("button").map { _1["tabindex"] }
  end
end
