# frozen_string_literal: true

require "application_system_test_case"

# posts#show subscribes to the post's own stream, and Post#broadcast_live_refresh
# sends a refresh on every commit to it — a vote, a new comment from someone else.
# Refreshes morph (Shared::ApplicationSetup turbo_refreshes_with :morph), and a
# morph rebuilds the page from server HTML, which has no editor in it: Tiptap's
# contenteditable exists only in the browser. This drives that refresh with a
# half-written comment open.
class TiptapMorphTest < ApplicationSystemTestCase
  test "a half-written comment survives the refresh a post broadcasts" do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    city = City.find_by!(domain: "brgen.no")
    author = User.strict_loading(false).create!(
      email_address: "tiptap-morph-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city:,
    )
    post_record = ActsAsTenant.with_tenant(city) { Post.create!(user: author, title: "Tråd", content: "…", city:) }

    visit post_path(post_record)
    find("#comment_form textarea, form textarea[name='comment[content]']", visible: :all).click
    editor = find(".tiptap_area[contenteditable=true]", wait: 10)
    editor.send_keys("Halvskrevet svar")
    assert_selector ".tiptap_area", text: "Halvskrevet svar"

    page.execute_script(<<~JS)
      window.__morphed = false
      document.addEventListener("turbo:morph", () => { window.__morphed = true }, { once: true })
      Turbo.session.refresh(location.href)
    JS
    assert Timeout.timeout(10) { sleep 0.1 until page.evaluate_script("window.__morphed"); true }, "the refresh never morphed"

    assert_selector ".tiptap_area[contenteditable=true]", text: "Halvskrevet svar", wait: 2
  end
end
