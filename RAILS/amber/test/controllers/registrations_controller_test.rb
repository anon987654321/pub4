# frozen_string_literal: true

require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  # The controller saved into a local, so a failed signup re-rendered a blank
  # User.new and the visitor never learned why nothing happened.
  test "a failed signup says why and keeps the email" do
    post registration_url, params: {
      accept_terms: "1", accept_age: "1",
      user: {
        email_address: "new-person@example.com",
        password: "long-enough-pass",
        password_confirmation: "does-not-match"
      }
    }

    assert_response :unprocessable_entity
    assert_select "section.errors[role=alert]"
    assert_select "input[name='user[email_address]'][value='new-person@example.com']"
  end

  test "a signed-in user is sent past sign-up, and a second post creates nothing" do
    post registration_url, params: {
      accept_terms: "1", accept_age: "1",
      user: { email_address: "already@example.com", password: "long-enough-pass", password_confirmation: "long-enough-pass" }
    }
    assert_redirected_to root_path

    account = User.find_by!(email_address: "already@example.com")
    refute account.email_verified?
    assert_predicate account.email_verification_token, :present?

    get new_registration_url
    assert_redirected_to root_path

    assert_no_difference -> { User.count } do
      post registration_url, params: {
        accept_terms: "1", accept_age: "1",
        user: { email_address: "second@example.com", password: "long-enough-pass", password_confirmation: "long-enough-pass" }
      }
    end
    assert_redirected_to root_path
  end

  test "registration shares the configured identity providers with sign-in" do
    previous = Rails.application.config.x.oauth_provider_slugs
    begin
      Rails.application.config.x.oauth_provider_slugs = %w[bankid vipps google_oauth2 facebook]
      get new_registration_url

      assert_response :success
      assert_select 'nav.oauth-links'
      assert_select 'form[action="/auth/vipps"]'
      assert_select 'form[action="/auth/google_oauth2"]'
      assert_select 'form[action="/auth/facebook"]'
      assert_select 'form[action="/auth/bankid"]'
      refute_includes response.body, "/auth/github"
    ensure
      Rails.application.config.x.oauth_provider_slugs = previous
    end
  end


  test "unverified account cannot post as a claimed identity until email confirmation" do
    email = "confirm-#{SecureRandom.hex(4)}@example.com"
    post registration_url, params: {
      accept_terms: "1", accept_age: "1",
      user: { email_address: email, password: "long-enough-pass", password_confirmation: "long-enough-pass" }
    }

    assert_redirected_to root_path
    account = User.find_by!(email_address: email)
    refute account.email_verified?

    assert_no_difference -> { Post.count } do
      post posts_url, params: { post: { body: "A first post before email confirmation" } }
    end
    assert_redirected_to root_path

    get verify_email_path(account.email_verification_token)
    assert_redirected_to root_path
    assert account.reload.email_verified?

    assert_difference -> { Post.count }, 1 do
      post posts_url, params: { post: { body: "A post after email confirmation" } }
    end
    assert_redirected_to posts_url
  end

end
