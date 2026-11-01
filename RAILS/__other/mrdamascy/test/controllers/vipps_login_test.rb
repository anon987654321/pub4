# frozen_string_literal: true

require "test_helper"

# "Logg inn med Vipps" (APP_SPEC §12): the zero-typing path into checkout.
# Mock mode runs the whole loop against our own stand-in page; real mode is
# exercised with the stubbed HTTP core. Guarantees: state is verified, the
# profile fills blanks but never clobbers, and ?to=checkout returns the
# customer to the confirm screen with everything prefilled.
class VippsLoginTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
  end

  teardown do
    vipps_restore_http!
  end

  # --- Mock mode -------------------------------------------------------------

  test "mock vipps_auth bounces to the mock consent page and stores state" do
    get session_vipps_path

    assert_response :redirect
    assert_match(%r{/vipps/login_mock}, response.redirect_url)
    follow_redirect!
    assert_response :success
    assert_match(/Telefon/, response.body)
  end

  test "mock callback creates the user, signs in and clears state" do
    get session_vipps_path
    state = session[:vipps_login_state]

    get session_vipps_callback_path, params: { state: state, phone: "90000007", name: "Kader B" }

    assert_redirected_to root_path
    user = User.find_by!(phone: "90000007")
    assert_equal "Kader B", user.name
    assert cookies[:session_token].present?
    assert_nil session[:vipps_login_state], "the one-time state must be burned"
  end

  test "mock callback with a state mismatch refuses to sign in" do
    get session_vipps_path

    get session_vipps_callback_path, params: { state: "forged", phone: "90000007" }

    assert_redirected_to new_session_path
    assert_nil User.find_by(phone: "90000007"), "a forged state must never create a user"
    assert cookies[:session_token].blank?
  end

  test "mock callback with ?to=checkout lands back on the confirm screen" do
    get session_vipps_path, params: { to: "checkout" }
    state = session[:vipps_login_state]

    get session_vipps_callback_path, params: { state: state, phone: "90000007", name: "Ola" }

    assert_redirected_to checkout_path, "login from checkout must return to checkout"
  end

  test "mock callback without a usable phone refuses" do
    get session_vipps_path
    state = session[:vipps_login_state]

    get session_vipps_callback_path, params: { state: state, phone: "12" }

    assert_redirected_to new_session_path
    assert_nil User.find_by(phone: "12")
  end

  # --- Real mode (stubbed HTTP) ------------------------------------------------

  test "real vipps_auth redirects to the Vipps authorize endpoint" do
    ENV["VIPPS_MOCK"] = "0"
    ENV["VIPPS_CLIENT_ID"] = "vip-cid"
    ENV["VIPPS_CLIENT_SECRET"] = "vip-secret"
    ENV["VIPPS_SUBSCRIPTION_KEY"] = "vip-sub"
    ENV["VIPPS_MSN"] = "123456"

    get session_vipps_path, params: { to: "checkout" }

    assert_response :redirect
    assert_match(%r{\Ahttps://api\.vipps\.no/access-management-1\.0/access/oauth2/auth}, @response.redirect_url)
  ensure
    vipps_restore_http!
  end

  test "real callback maps the userinfo profile and fills blanks only" do
    vipps_real_mode!
    existing = User.create!(phone: "90000004", name: "Bestemt Navn", role: ROLES.fetch(:customer),
                            default_address: "Min gata 1", default_postcode: "5003")

    get session_vipps_path, params: { to: "checkout" }
    state = session[:vipps_login_state]
    get session_vipps_callback_path, params: { state: state, code: "vip-code" }

    assert_redirected_to checkout_path
    existing.reload
    assert_equal "90000004", existing.phone, "47-prefixed Vipps profile must resolve to the same row"
    assert_equal "Bestemt Navn", existing.name, "never clobber a chosen name"
    assert_equal "Min gata 1", existing.default_address, "never clobber a typed address"
    assert_equal "5003", existing.default_postcode
    assert_equal 1, User.where(phone: "90000004").count, "no duplicate identity"
  end

  test "real callback for a brand-new phone creates the profile from Vipps data" do
    vipps_real_mode!

    get session_vipps_path, params: { to: "checkout" }
    state = session[:vipps_login_state]
    get session_vipps_callback_path, params: { state: state, code: "vip-code" }

    assert_redirected_to checkout_path
    user = User.find_by!(phone: "90000004")
    assert_equal "Ola Nordmann", user.name
    assert_equal "Nygårdsgaten 12, 5015 Bergen", user.default_address
    assert_equal "5015", user.default_postcode
  end
end
