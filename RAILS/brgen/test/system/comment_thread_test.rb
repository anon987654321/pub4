# frozen_string_literal: true

require "application_system_test_case"

# The comment thread on posts#show in a browser: the Reply disclosure, a
# finished reply, the collapse toggle, and live comments that arrive while the
# reader is above the end of the thread (comment_thread_controller,
# live_comments_controller).
class CommentThreadTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(
      email_address: "thread-#{SecureRandom.hex(4)}@brgen.no", username: "traad_#{SecureRandom.hex(3)}",
      password: "password123", city: @city, guest: false, email_verified_at: Time.current,
    )
    @post = ActsAsTenant.with_tenant(@city) { Post.create!(user: @author, title: "Tråd", content: "…", city: @city) }
    @root = Comment.create!(user: @author, commentable: @post, content: "<p>Første kommentar</p>")
  end

  def sign_in
    visit_city(nil, "/")
    decline_optional_cookies
    sign_in_on_city(@author)
  end

  # Comment#broadcast_to_thread reaches the page once its stream is subscribed.
  def await_live_thread
    assert_selector "turbo-cable-stream-source[connected]", visible: :all, wait: 10
  end

  def active_element_inside?(selector)
    page.evaluate_script("document.activeElement && document.activeElement.closest(#{selector.to_json}) !== null")
  end

  test "opening Reply puts the caret in the reply editor" do
    sign_in
    visit_city(nil, post_path(@post))

    find("#reply_disclosure_comment_#{@root.id} > summary").click

    assert wait_until { active_element_inside?("#reply_form_#{@root.id}") }, "focus stayed off the reply editor"
  end

  test "a finished reply closes its disclosure and takes focus" do
    sign_in
    visit_city(nil, post_path(@post))

    find("#reply_disclosure_comment_#{@root.id} > summary").click
    editor = find("#reply_form_#{@root.id} .tiptap_area[contenteditable=true]", wait: 10)
    editor.send_keys("Et svar")
    find("#reply_form_#{@root.id} input[type=submit]").click

    reply = nil
    assert wait_until { reply = Comment.find_by(parent_id: @root.id) }, "the reply was not saved"
    assert_selector "#replies_comment_#{@root.id} #comment_#{reply.id}", wait: 5
    assert_no_selector "#reply_disclosure_comment_#{@root.id}[open]"
    assert wait_until { active_element_inside?("#comment_#{reply.id}") }, "the new reply did not take focus"
  end

  test "the collapse toggle hides a comment and its replies and counts them" do
    first = Comment.create!(user: @author, commentable: @post, content: "<p>Svar én</p>", parent_id: @root.id)
    Comment.create!(user: @author, commentable: @post, content: "<p>Svar to</p>", parent_id: first.id)
    visit_city(nil, post_path(@post))

    toggle = find("#comment_#{@root.id} > article > header > button.comment-collapse")
    assert_equal "true", toggle["aria-expanded"]
    toggle.click

    assert_equal "false", toggle["aria-expanded"]
    assert_equal I18n.t("comments.expand_replies.other").sub("%{count}", "2"), toggle.text
    assert_no_selector "#comment_#{@root.id} > article > .comment-body", visible: true
    assert_no_selector "#replies_comment_#{@root.id}", visible: true
    status = find("#comment_#{@root.id} > article > header > [role=status]", visible: :all)
    assert_equal I18n.t("comments.hidden_replies.other").sub("%{count}", "2"), status.text(:all)

    toggle.click
    assert_selector "#comment_#{@root.id} > article > .comment-body", text: "Første kommentar"
    assert_selector "#replies_comment_#{@root.id}", visible: true
  end

  test "a live comment waits behind a chip while the reader is above the end" do
    long = "<p>#{"Lang kommentar. " * 20}</p>"
    25.times { Comment.create!(user: @author, commentable: @post, content: long) }
    visit_city(nil, post_path(@post))
    decline_optional_cookies
    page.execute_script("window.scrollTo(0, 0)")

    await_live_thread
    late = Comment.create!(user: @author, commentable: @post, content: "<p>Kom sent</p>")

    label = I18n.t("comments.new_comments.one").sub("%{count}", "1")
    chip = find("button.comments-new-chip", text: label, wait: 5)
    assert_no_selector "#comment_#{late.id}"

    chip.click
    assert_selector "#comment_#{late.id}", text: "Kom sent", wait: 5
    assert_no_selector "button.comments-new-chip", visible: true
  end

  test "a live comment lands straight away when the reader is at the end" do
    visit_city(nil, post_path(@post))
    decline_optional_cookies
    scroll_to(find("#comments", visible: :all), align: :bottom)
    await_live_thread
    late = Comment.create!(user: @author, commentable: @post, content: "<p>Rett inn</p>")

    assert_selector "#comment_#{late.id}", text: "Rett inn", wait: 5
    assert_no_selector "button.comments-new-chip", visible: true
  end
end
