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

  # RI-012: login transfers the persisted guest, rotates browser state and survives refresh.
  def test_RI_012_authentication_rotates_session_and_survives_refresh
    get new_session_path
    guest_id = session[:guest_user_id]
    assert_predicate guest_id, :present?
    assert User.find(guest_id).guest?

    post session_path, params: { email_address: @user.email_address, password: "password123" }

    assert_response :redirect
    authenticated_session = @user.sessions.reload.sole
    assert_equal authenticated_session.id, cookies.signed[:session_id]
    assert_equal guest_id, session[:previous_guest_user_id], "the pre-auth guest reference should survive only as migration context"
    refute session[:guest_user_id], "the registered browser must not continue as the guest"
    refute User.find(guest_id).guest?, "guest history must be transferred before sign-in completes"

    get root_path

    assert_response :success
    assert_equal @user.id, controller.send(:current_user)&.id
    assert Session.exists?(authenticated_session.id), "refresh lost the authenticated session"
  end

  test "a same-origin csrf header is accepted for a write" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    https!

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
    assert_equal 1, @user.sessions.reload.count, "the same-origin write did not sign in"
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  # RI-001: a successful public signup creates a real account but does not
  # silently mark an unconfirmed email address as verified.
  def test_RI_001_valid_signup_persists_unverified_account
    email = "ri001-#{SecureRandom.hex(6)}@example.test"
    username = "ri001_#{SecureRandom.hex(5)}"
    params = {
      user: {
        email_address: email,
        username:,
        password: "password123",
        password_confirmation: "password123"
      },
      accept_terms: "1",
      accept_age: "1"
    }

    assert_difference("User.count", 1) do
      post users_path, params:
    end

    assert_response :redirect
    account = User.find_by!(email_address: email)
    refute account.guest?
    refute account.email_verified?
    assert_predicate account.email_verification_token, :present?
  end

  # RI-011: expire the authenticated session after the form opens. The bad
  # CSRF request and the stale-session request must both leave server state alone.
  def test_RI_011_expired_session_with_csrf_failure_refuses_mutation
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    https!

    get new_session_path
    login_token = controller.send(:form_authenticity_token)
    same_origin = {
      "Sec-Fetch-Site" => "same-origin",
      "Origin" => "https://brgen.no"
    }
    post session_path,
         params: { email_address: @user.email_address, password: "password123" },
         headers: same_origin.merge("X-CSRF-Token" => login_token)
    assert_response :redirect

    get new_community_path
    assert_response :success
    form_token = controller.send(:form_authenticity_token)
    session_row = @user.sessions.reload.sole
    session_row.destroy
    name = "RI011#{SecureRandom.hex(4)}"
    params = { community: { name:, description: "interaction campaign session boundary" } }

    # Rails accepts a same-origin request on the strength of Sec-Fetch-Site alone, so a forged one is
    # cross-site; an invalid token on a same-origin request is not a forgery.
    forged = { "Sec-Fetch-Site" => "cross-site", "Origin" => "https://attacker.example" }
    post communities_path, params:, headers: forged.merge("X-CSRF-Token" => "invalid")
    assert_response :unprocessable_entity
    assert_equal 0, Community.where(name: name).count, "the CSRF refusal mutated server state"

    post communities_path, params:, headers: same_origin.merge("X-CSRF-Token" => form_token)
    assert_response :redirect
    assert_equal 0, Community.where(name: name).count, "an expired server session mutated server state"
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
    assert_not_equal @user.id, controller.send(:current_user)&.id
    assert_not Session.exists?(session_row.id), "the session row survived the deletion marker"
  end

  test "destroying the session row signs the browser out" do
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    session_row = @user.sessions.reload.sole

    session_row.destroy
    get root_path

    assert_nil controller.send(:find_session_by_cookie), "a revoked session still resumed"
  end
end
