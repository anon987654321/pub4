# frozen_string_literal: true

require "test_helper"

# The controller loaded @comments and @comment and create.turbo_stream
# appended to #port_comments, but the port page drew neither a list nor a
# form, so a comment could be neither read nor written there.
class PortCommentsTest < ActionDispatch::IntegrationTest
  def test_a_guest_reads_the_thread_and_is_asked_to_sign_in
    port = seed_port
    Comment.create!(user: seed_user, port:, content: "builds fine on arm64")

    get port_path(port)
    assert_response :success
    assert_select "section#comments #port_comments article", text: /builds fine on arm64/
    assert_select "#port_comment_form", count: 0
    assert_select "section#comments a[href=?]", new_session_path
  end

  def test_a_signed_in_reader_gets_a_labelled_form
    port = seed_port
    sign_in(seed_user)

    get port_path(port)
    assert_response :success
    assert_select "#port_comments_empty", text: I18n.t("ports.comments_none")
    assert_select "form#port_comment_form[action=?]", port_comments_path(port) do
      assert_select "label[for=comment_content]", text: I18n.t("ports.write_comment")
      assert_select "textarea[name='comment[content]']"
    end
  end

  def test_the_form_posts_a_comment_and_drops_the_empty_state
    port = seed_port
    sign_in(seed_user)

    post port_comments_path(port), params: { comment: { content: "needs a patch on sparc64" } }, as: :turbo_stream
    assert_response :success
    assert_equal "needs a patch on sparc64", port.comments.last.content
    assert_includes response.body, %(action="remove" target="port_comments_empty")
    assert_includes response.body, %(name="comment[content]")
  end

  private

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def seed_user
    User.strict_loading(false).create!(email_address: "c-#{SecureRandom.hex(4)}@bsdports.test", password: "password")
  end

  def seed_port
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.4", pkgpath: "devel/git")
  end
end
