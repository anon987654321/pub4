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
        password_confirmation: "does-not-match",
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

  test "email signup transfers anonymous posts and MASTER chat to the new account" do
    post_body = "Anonymous before signup #{SecureRandom.hex(4)}"
    post posts_url, params: { post: { body: post_body, anonymous: true } }
    assert_redirected_to root_path
    anonymous_post = Post.find_by!(body: post_body)
    guest = User.find(anonymous_post.user_id)
    assert guest.guest?

    post invite_master_messages_path
    assert_redirected_to messages_path
    master = User.find_by!(email_address: "master@amber.local", bot: true)
    chat_body = "Guest chat before signup #{SecureRandom.hex(4)}"
    post messages_path, params: { message: { recipient_id: master.id, body: chat_body } }
    assert_redirected_to messages_path
    outgoing = Message.find_by!(sender_id: guest.id, recipient_id: master.id, body: chat_body)
    incoming = Message.find_by!(sender_id: master.id, recipient_id: guest.id)

    email = "merged-#{SecureRandom.hex(5)}@example.test"
    post registration_url, params: {
      accept_terms: "1", accept_age: "1",
      user: { email_address: email, password: "long-enough-pass", password_confirmation: "long-enough-pass" }
    }

    assert_redirected_to root_path
    account = User.find_by!(email_address: email)
    assert_equal account.id, anonymous_post.reload.user_id
    assert anonymous_post.anonymous?, "account conversion must preserve anonymous presentation"
    assert_equal account.id, outgoing.reload.sender_id
    assert_equal account.id, incoming.reload.recipient_id
    refute guest.reload.guest?
    assert AccountMerge.exists?(guest_user_id: guest.id, user_id: account.id)
    refute account.email_verified?, "merging guest history must not bypass email verification"
  end

  test "signup leaves guest history and session intact when transfer is blocked" do
    post_body = "Guest post before blocked signup #{SecureRandom.hex(5)}"
    post posts_url, params: { post: { body: post_body, anonymous: true } }
    assert_redirected_to root_path
    guest_post = Post.find_by!(body: post_body)
    guest = User.find(guest_post.user_id)
    assert_equal guest.id, session[:guest_user_id]

    merger = Object.new
    merger.define_singleton_method(:call) do
      raise ActiveRecord::MigrationError, "simulated missing account_merges table"
    end
    email = "blocked-merge-#{SecureRandom.hex(5)}@example.test"

    AccountMerger.stub(:new, ->(**_kwargs) { merger }) do
      post registration_url, params: {
        accept_terms: "1", accept_age: "1",
        user: { email_address: email, password: "long-enough-pass", password_confirmation: "long-enough-pass" }
      }
    end

    assert_redirected_to root_path
    assert_equal I18n.t("shared.email_verification.signup_guest_merge_failed"), flash[:alert]
    assert_equal guest.id, session[:guest_user_id], "the failed transfer must not rotate the guest session"
    assert guest.reload.guest?
    assert_equal guest.id, guest_post.reload.user_id
    assert User.exists?(email_address: email), "account creation should remain durable"
    refute User.find_by!(email_address: email).email_verified?
    assert_empty AccountMerge.where(guest_user_id: guest.id)
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
