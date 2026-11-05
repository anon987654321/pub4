# frozen_string_literal: true

require "application_system_test_case"

# The feed card's more-actions list, driven by a keyboard and a real clipboard.
class PostCardActionsTest < ApplicationSystemTestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    city = City.find_by!(domain: "brgen.no")
    author = User.strict_loading(false).create!(
      email_address: "post-card-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city:,
    )
    @post = ActsAsTenant.with_tenant(city) { Post.create!(user: author, title: "Kortet", content: "Tekst", city:) }
  end

  # The front page greets a first visit with a welcome dialog and a cookie
  # question; a visitor answers both before using the feed.
  def visit_feed
    visit root_path
    decline_optional_cookies if has_css?("#cookie-consent-banner", wait: 3)
    find("button.welcome-onboarding-close", wait: 5).click if has_css?("button.welcome-onboarding-close", wait: 3)
    assert_no_selector "button.welcome-onboarding-close"
  end

  # Centred, so the open list is not under the sticky composer bar.
  def menu_button
    button = find("##{ActionView::RecordIdentifier.dom_id(@post)} .feed-action-menu > button")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", button)
    button
  end

  def active_element_id = page.evaluate_script("document.activeElement.id || document.activeElement.textContent.trim()")

  # Headless Chrome answers clipboard reads only for an origin granted them.
  def grant_clipboard
    browser = page.driver.browser
    browser.execute_cdp("Browser.grantPermissions", origin: URI.join(current_url, "/").to_s.chomp("/"),
                                                    permissions: %w[clipboardReadWrite clipboardSanitizedWrite])
  end

  def clipboard_text = evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")

  test "Copy link writes the post's address to the clipboard" do
    visit_feed
    grant_clipboard
    menu_button.click
    # From the keyboard: the list put focus on Copy link when it opened.
    find_button(I18n.t("post.copy_link")).send_keys(:enter)

    assert_selector "button", text: I18n.t("posts.link_copied")
    assert_equal URI.join(current_url, post_path(@post)).to_s, clipboard_text
  end

  test "the more-actions list takes focus, closes on Escape and hands focus back" do
    visit_feed
    button = menu_button
    button.click

    assert_equal "true", button["aria-expanded"]
    assert_equal I18n.t("post.copy_link"), active_element_id, "the first item should take focus on open"

    page.send_keys(:escape)

    assert_equal "false", button["aria-expanded"]
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(@post, :actions)}", visible: true
    assert page.evaluate_script("document.activeElement === arguments[0]", button), "focus should return to the trigger"
  end
end
