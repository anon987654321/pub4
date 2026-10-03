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
end
