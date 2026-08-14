# frozen_string_literal: true

require "test_helper"

# The quota wall tells a guest to "Sign up to post more". Until this existed
# there was nowhere to sign up: /users/new was a 404, the sign-in page only
# offered sign-in, and the OAuth buttons render only for providers configured
# in the environment.
class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  test "signup form is reachable without an account" do
    get new_user_path
    assert_response :success
    # Assert the translation, not the English string. brgen.no renders in nb, so
    # a literal "Create account" started failing the moment the page was
    # localised — through the key it follows whatever locale the host resolves to.
    assert_includes response.body, I18n.t("auth.create_account")
  end

  test "the sign-in page offers a way to create an account" do
    get new_session_path
    assert_response :success
    assert_match(new_user_path, response.body)
  end

  test "creating an account signs the visitor in as a real user" do
    post users_path, params: { accept_terms: "1", accept_age: "1", user: {
      email_address: "newcomer@example.test",
      username: "newcomer",
      password: "password123",
      password_confirmation: "password123"
    } }
    assert_redirected_to root_path

    user = User.find_by(email_address: "newcomer@example.test")
    assert user, "expected the account to exist"
    assert_not user.guest?
    assert user.sessions.any?, "expected a session for the new account"
  end

  test "signup carries the guest's posts onto the new account" do
    # The first hit builds a soft guest without writing a row; the second, which
    # carries the session cookie back, is what mints it (Shared::Authentication).
    get live_path
    get live_path
    guest = User.where(guest: true).order(created_at: :desc).first
    guest.update_columns(latitude: 60.39, longitude: 5.32, location_updated_at: Time.current)
    post live_path, params: { post: { content: "Guest note before signing up" } }
    guest_post = Post.where(user: guest).order(created_at: :desc).first
    assert guest_post, "expected the guest to have posted"

    post users_path, params: { accept_terms: "1", accept_age: "1", user: {
      email_address: "carryover@example.test",
      password: "password123",
      password_confirmation: "password123"
    } }
    assert_redirected_to root_path

    user = User.find_by(email_address: "carryover@example.test")
    assert_equal user.id, Post.strict_loading(false).find(guest_post.id).user_id
  end

  test "signup without accepting terms creates no account" do
    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params: { user: {
        email_address: "noterms@example.test",
        password: "password123",
        password_confirmation: "password123"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "an invalid signup re-renders the form instead of erroring" do
    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params: { user: { email_address: "", password: "x", password_confirmation: "y" } }
    end
    assert_response :unprocessable_entity
  end
end
