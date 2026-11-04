# frozen_string_literal: true

require "test_helper"

# A guest got a "Run MASTER review" button that posts to an authenticated
# route and bounced them to sign-in, and an empty "Port actions" nav where
# the Watch button would be.
class PortGuestActionsTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    @port = Port.create!(platform:, category:, name: "git", version: "2.4", pkgpath: "devel/git")
  end

  test "a guest is offered sign-in instead of the review and watch buttons" do
    get port_path(@port)
    assert_response :success
    assert_select "form[action=?]", review_port_path(@port), 0
    assert_select "a[href=?]", new_session_path, text: I18n.t("ports.sign_in_to_review")
    assert_select "nav[aria-label=?] a[href=?]", I18n.t("ports.actions_label"), new_session_path,
                  text: I18n.t("ports.sign_in_to_watch")
  end

  test "a signed-in reader keeps the review button" do
    email = "g-#{SecureRandom.hex(4)}@bsdports.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }

    get port_path(@port)
    assert_select "form[action=?]", review_port_path(@port), 1
  end
end
