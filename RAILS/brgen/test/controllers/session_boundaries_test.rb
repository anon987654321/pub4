# frozen_string_literal: true

require "test_helper"

# Two edges of a signed-in session that nothing exercised. The test environment
# turns forgery protection off, so a write without a token passed every other
# test here; and the sign-in cookie is permanent, so the Session row is the only
# thing that can end one from the server side.
class SessionBoundariesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "boundaries@brgen.no", password: "password123",
      username: "boundaries", guest: false, city: @city
    )
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a write without an authenticity token is refused" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post session_path, params: { email_address: @user.email_address, password: "password123" }

    assert_response :unprocessable_entity
    assert_empty @user.sessions.reload, "a forged sign-in created a session"
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "destroying the session row signs the browser out" do
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    session_row = @user.sessions.reload.sole

    session_row.destroy
    get root_path

    assert_nil controller.send(:find_session_by_cookie), "a revoked session still resumed"
  end
end
