# frozen_string_literal: true

require "test_helper"

# The Rails 8.2 boundary is Fetch Metadata first: same-site writes pass without a token, while cross-site writes are rejected. A form token remains a compatible secondary signal.
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

  test "a cross-site write is refused by the fetch-metadata check" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post session_path,
         params: { email_address: @user.email_address, password: "password123" },
         headers: { "Sec-Fetch-Site" => "cross-site" }

    assert_response :unprocessable_entity
    assert_empty @user.sessions.reload, "a cross-site sign-in created a session"
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a same-origin write is accepted without a csrf token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post session_path,
         params: { email_address: @user.email_address, password: "password123" },
         headers: { "Sec-Fetch-Site" => "same-origin" }

    assert_response :redirect
    assert_equal @user.id, controller.current_user.id
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a same-origin form token remains accepted" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get new_session_path
    token = controller.send(:form_authenticity_token)

    post session_path,
         params: {
           authenticity_token: token,
           email_address: @user.email_address,
           password: "password123"
         },
         headers: { "Sec-Fetch-Site" => "same-origin" }

    assert_response :redirect
    assert_equal @user.id, controller.current_user.id
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a header-only csrf token is accepted for a write" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get new_session_path
    token = controller.send(:form_authenticity_token)

    post session_path,
         params: { email_address: @user.email_address, password: "password123" },
         headers: { "X-CSRF-Token" => token }

    assert_response :redirect
    assert_equal @user.id, controller.current_user.id
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a legacy hidden authenticity token is accepted for a write" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get new_session_path
    token = controller.send(:form_authenticity_token)

    post session_path,
         params: {
           authenticity_token: token,
           email_address: @user.email_address,
           password: "password123"
         }

    assert_response :redirect
    assert_equal @user.id, controller.current_user.id
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a deletion marker revokes an already-issued session" do
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    session_row = @user.sessions.reload.sole

    @user.schedule_deletion!
    get root_path

    assert_nil controller.send(:find_session_by_cookie), "deletion must revoke an existing session"
    assert_empty @user.sessions.reload, "a departing account must have no usable session rows"
    assert_not_equal @user.id, controller.current_user&.id
    assert_predicate session_row, :destroyed?
  end

  test "destroying the session row signs the browser out" do
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    session_row = @user.sessions.reload.sole

    session_row.destroy
    get root_path

    assert_nil controller.send(:find_session_by_cookie), "a revoked session still resumed"
  end
end
