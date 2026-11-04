# frozen_string_literal: true

require "test_helper"

# Port URLs were bare ids, and set_port decoded the param with tr("-", "/"),
# so devel/py-foo could never be reached by its pkgpath. Comments looked the
# port up with a plain find, a second rule for the same URL segment.
class PortUrlsTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    @port = Port.create!(platform:, category:, name: "py-foo", version: "1", pkgpath: "devel/py-foo")
  end

  test "a port URL names its pkgpath and leads back to the port" do
    assert_equal "/ports/#{@port.id}-devel-py-foo", port_path(@port)

    get port_path(@port)
    assert_response :success
    assert_select "h1", text: /py-foo/
  end

  test "comments are found under the same URL segment as the port page" do
    email = "u-#{SecureRandom.hex(4)}@bsdports.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }

    post port_comments_path(@port), params: { comment: { content: "fine on amd64" } }

    assert_redirected_to port_path(@port)
    assert_equal [ "fine on amd64" ], @port.comments.pluck(:content)
  end
end
