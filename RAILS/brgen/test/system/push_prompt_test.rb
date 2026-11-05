# frozen_string_literal: true

require "application_system_test_case"

# Push permission is asked for in context, after something answerable.
class PushPromptTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @reader = person("chrome_reader_#{SecureRandom.hex(2)}")
    @friend = person("chrome_friend_#{SecureRandom.hex(2)}")
  end

  # On 127.0.0.1 rather than brgen.no: a secure context, where the browser
  # offers the Push API at all.
  test "push is asked for after the reader's first message, not on arrival, and only once" do
    conversation = thread_with_line_from_friend("Hei")
    browser = page.driver.browser
    browser.execute_cdp("Browser.setPermission", permission: { name: "notifications" }, setting: "prompt")
    visit "/session/new"
    decline_optional_cookies if page.has_css?("#cookie-consent-banner", wait: 2)
    fill_in "email_address", with: @reader.email_address
    fill_in "password", with: "password123"
    find("input[type=submit][value='#{I18n.t("auth.sign_in")}']").click
    assert wait_until { Session.exists?(user_id: @reader.id) }
    visit "/conversations/#{conversation.id}"

    assert_equal "default", page.evaluate_script("Notification.permission")
    assert_selector "#push-prompt", visible: :hidden
    send_line("Ja, gjerne")
    assert_selector "#push-prompt", visible: true, text: I18n.t("push.context_prompt"), wait: 5
    within("#push-prompt") { click_button I18n.t("push.not_now") }
    assert_selector "#push-prompt", visible: :hidden

    send_line("Ses i morgen")
    assert wait_until { conversation.messages.exists?(content: "Ses i morgen") }
    assert_no_selector "#push-prompt", visible: true, wait: 2
  end

  private

  def thread_with_line_from_friend(text)
    conversation = ActsAsTenant.with_tenant(@city) { Conversation.find_or_create_direct(@reader, @friend) }
    ActsAsTenant.with_tenant(@city) do
      conversation.messages.create!(sender: @friend, content: text, message_type: "text")
    end
    conversation
  end

  def send_line(text)
    fill_in "message_content", with: text
    find("#new_message input[type=submit]").click
  end

  def person(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end
end
