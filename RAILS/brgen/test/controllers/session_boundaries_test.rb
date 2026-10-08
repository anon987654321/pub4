# frozen_string_literal: true

require "test_helper"

# Rails 8.2 uses request metadata for the default CSRF verification path.
# These tests pin the browser boundary and keep a legacy token from becoming a
# cross-site bypass while the application still renders standard Rails forms.
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

  test "a cross-site write without csrf metadata is refused" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    post session_path,
         params: { email_address: @user.email_address, password: "password123" },
         headers: {
           "Sec-Fetch-Site" => "cross-site",
           "Origin" => "https://attacker.example"
         }

    assert_response :unprocessable_entity
    assert_empty @user.sessions.reload, "a forged sign-in created a session"
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a same-origin csrf header is accepted for a write" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get new_session_path
    token = controller.send(:form_authenticity_token)

    post session_path,
         params: { email_address: @user.email_address, password: "password123" },
         headers: {
           "X-CSRF-Token" => token,
           "Sec-Fetch-Site" => "same-origin",
           "Origin" => "https://brgen.no"
         }

    assert_response :redirect
    assert_equal @user.id, controller.current_user.id
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "a legacy hidden authenticity token cannot bypass cross-site csrf" do
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
         headers: {
           "Sec-Fetch-Site" => "cross-site",
           "Origin" => "https://attacker.example"
         }

    assert_response :unprocessable_entity
    assert_empty @user.sessions.reload, "a legacy hidden token bypassed header-only csrf"
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
