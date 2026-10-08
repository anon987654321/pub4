# frozen_string_literal: true

require "test_helper"

# Every vertical is a subdomain of the city apex. The session cookies were
# host-only, so a browser stopped sending them at the first vertical link:
# signing in on brgen.no and clicking through to markedsplass.brgen.no landed
# you there as a fresh guest with an empty cart.
class CrossSubdomainSessionTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "spanning@brgen.no", password: "password123", username: "spanning", guest: false
    )
  end

  test "the session cookies are scoped to the apex, not to one host" do
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password123" }

    set_cookies = Array(response.headers["set-cookie"]).flat_map { |h| h.split("\n") }
    session_id = set_cookies.find { |c| c.start_with?("session_id=") }
    app_session = set_cookies.find { |c| c.start_with?("_app_session=") }

    # RFC 6265: a Domain attribute always covers subdomains, dot or no dot.
    assert_match(/domain=\.?brgen\.no/i, session_id.to_s)
    assert_match(/domain=\.?brgen\.no/i, app_session.to_s)
  end

  test "a sign-in on the apex still holds on a vertical subdomain" do
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    assert_redirected_to root_path

    host! "markedsplass.brgen.no"
    get account_path # require_real_user -- a guest is redirected to sign-in
    assert_response :success
  end

  test "a guest keeps one identity across verticals" do
    host! "brgen.no"
    # Two requests to get one guest, on purpose: the first sighting builds a
    # soft guest without saving it, and the row is written when the browser
    # returns the session cookie. See Shared::Authentication.
    assert_no_difference -> { User.where(guest: true).count } do
      get root_path
    end
    get root_path
    guest = User.where(guest: true).order(created_at: :desc).first
    assert guest.persisted?

    host! "takeaway.brgen.no"
    get takeaway.root_path
    assert_response :success
    assert_equal guest.id, User.where(guest: true).order(created_at: :desc).first.id,
      "a second guest was minted for the takeaway subdomain"
  end
end
