# frozen_string_literal: true

require "application_system_test_case"

# The messenger's behaviour in a browser: what the conversation pane does once
# JavaScript runs. Request-level tests see the markup; these see what a reader
# sees.
class MessengerChromeTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @reader = person("chrome_reader_#{SecureRandom.hex(2)}")
    @friend = person("chrome_friend_#{SecureRandom.hex(2)}")
  end

  test "Reply fills the composer in place, and the reply is sent as one" do
    conversation = thread_with_line_from_friend("Kino i kveld?")
    line = conversation.messages.last
    open_thread(conversation)

    within("##{ActionView::RecordIdentifier.dom_id(line)}") do
      open_actions
      click_link I18n.t("messages.reply")
    end
    within("#new_message") do
      assert_selector "[data-message-reply-line]", text: "Kino i kveld?"
      assert_equal line.id.to_s, find("input[name=\"message[parent_id]\"]", visible: :hidden).value
    end
    assert_log_kept
    assert_equal "message_content", page.evaluate_script("document.activeElement.id")

    fill_in "message_content", with: "Ja!"
    find("#new_message input[type=submit]").click
    assert wait_until { conversation.messages.exists?(parent_id: line.id, content: "Ja!") },
           "the reply was not threaded"
  end

  test "Edit swaps only the composer, lands at the end of the text, and Escape cancels" do
    conversation = ActsAsTenant.with_tenant(@city) { Conversation.find_or_create_direct(@reader, @friend) }
    mine = ActsAsTenant.with_tenant(@city) do
      conversation.messages.create!(sender: @reader, content: "Sees kl 8", message_type: "text")
    end
    open_thread(conversation)

    within("##{ActionView::RecordIdentifier.dom_id(mine)}") do
      open_actions
      click_link I18n.t("actions.edit")
    end
    assert_selector "form.messenger-edit-form textarea", wait: 10
    assert_log_kept
    caret = page.evaluate_script("(f => [f.id, f.selectionStart, f.value.length])(document.activeElement)")
    assert_equal [ "message_content", "Sees kl 8".length, "Sees kl 8".length ], caret

    find("form.messenger-edit-form textarea").send_keys(:escape)
    assert_selector "#new_message", wait: 5
    assert_no_selector "form.messenger-edit-form"
    assert_log_kept

    within("##{ActionView::RecordIdentifier.dom_id(mine)}") do
      open_actions
      click_link I18n.t("actions.edit")
    end
    find("form.messenger-edit-form textarea").send_keys(" eller 9")
    find("form.messenger-edit-form input[type=submit]").click
    assert_selector "#new_message", wait: 5
    assert wait_until { mine.reload.content == "Sees kl 8 eller 9" }
    assert_selector "##{ActionView::RecordIdentifier.dom_id(mine)}", text: "Sees kl 8 eller 9"
    assert_log_kept
  end

  test "a chosen photo shows as a thumbnail that can be taken off before sending" do
    conversation = thread_with_line_from_friend("Hei")
    open_thread(conversation)

    assert_selector ".messenger-composer-preview", visible: :hidden
    find("#new_message input[type=file]", visible: :all).attach_file(file_fixture("tiny.png"), make_visible: true)
    within(".messenger-composer-preview") do
      assert_selector "img[alt=?]".sub("?", I18n.t("messages.chosen_photo").inspect)
      click_button I18n.t("messages.remove_photo")
    end
    assert_selector ".messenger-composer-preview", visible: :hidden
    assert_equal 0, page.evaluate_script("document.querySelector(\"#new_message input[type=file]\").files.length")
  end

  test "a reader scrolled up on a phone gets a jump-to-latest button when a message arrives" do
    conversation = ActsAsTenant.with_tenant(@city) { Conversation.find_or_create_direct(@reader, @friend) }
    ActsAsTenant.with_tenant(@city) do
      40.times { |i| conversation.messages.create!(sender: @friend, content: "Linje #{i}", message_type: "text") }
    end
    open_thread(conversation, width: 390)
    page.execute_script("document.querySelector(\"#messages > li\").scrollIntoView()")
    assert_not page.evaluate_script(at_tail_js), "the reader is scrolled up"
    # A line arriving over the cable is a new child of the log; append one the
    # same way, so the test does not depend on the cable reaching the browser.
    page.execute_script(<<~JS)
      const log = document.getElementById("messages")
      const line = log.querySelector(":scope > li[id^=message_]:last-of-type").cloneNode(true)
      line.id = "message_arrived"
      log.append(line)
    JS

    find(".messenger-composer-area .conversation_unread_pill", wait: 5).click
    assert wait_until { page.evaluate_script(at_tail_js) }, "the button did not bring the newest line into view"
    assert_no_selector ".conversation_unread_pill"
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  private

  def at_tail_js = "document.getElementById('messages').getBoundingClientRect().bottom - window.innerHeight < 80"

  def thread_with_line_from_friend(text)
    conversation = ActsAsTenant.with_tenant(@city) { Conversation.find_or_create_direct(@reader, @friend) }
    ActsAsTenant.with_tenant(@city) do
      conversation.messages.create!(sender: @friend, content: text, message_type: "text")
    end
    conversation
  end

  # Marks the log, so a test can tell the pane was not reloaded under it.
  def open_thread(conversation, width: nil)
    sign_in_on_city(@reader)
    page.current_window.resize_to(width, 844) if width
    visit_city(nil, "/conversations/#{conversation.id}")
    decline_optional_cookies if page.has_css?("#cookie-consent-banner", wait: 1)
    assert_selector "#new_message"
    page.execute_script("document.getElementById(\"messages\").dataset.kept = \"1\"")
  end

  # The line's actions sit in a <details>; open it as a click on its summary does.
  def open_actions
    find("details.msg-actions").execute_script("this.open = true")
  end

  def assert_log_kept
    kept = page.evaluate_script("document.getElementById(\"messages\")?.dataset.kept")
    assert_equal "1", kept, "the log was reloaded"
  end

  def person(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end
end
