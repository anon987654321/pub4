# frozen_string_literal: true

require "test_helper"

# A failed comment from the port page rendered the full comments/new page
# into a Turbo stream request, so the reader's form never showed the error.
class CommentErrorsTest < ActionDispatch::IntegrationTest
  test "a blank comment comes back as the form with its errors" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    port = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")
    email = "ce-#{SecureRandom.hex(4)}@bsdports.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }

    post port_comments_path(port), params: { comment: { content: "" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(action="replace" target="port_comment_form")
    assert_includes response.body, %(class="errors" role="alert")
    assert_equal 0, port.comments.count
  end
end
