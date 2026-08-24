# frozen_string_literal: true

require "test_helper"

# The passwordless half of sign-in was built and unreachable: the columns, the
# unique index, the token generator, the validity check and the mailer all
# existed, and there was no route, no view template and no caller. The mailer
# aimed at `session_url(magic_token:)`, which is not a route in any of the three
# apps, via `Rails.application.routes.url_helpers`, which carries no host — so
# it raised, a rescue swallowed it, and the address it fell back to was a
# relative path.
#
# These tests are the reason none of that can go quiet again.
class PasswordlessSessionsTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email_address: "magic@example.com", password: "correct horse battery")
  end

  def test_requesting_a_link_mails_an_absolute_url_that_resolves
    assert_emails 1 do
      post request_magic_session_url, params: { email_address: @user.email_address }
    end

    mail = ActionMailer::Base.deliveries.last
    body = [ mail.html_part, mail.text_part ].compact.map { |part| part.body.to_s }.join
    token = @user.reload.magic_link_token

    assert_predicate token, :present?, "the request must mint a token"
    assert_includes body, "http", "a mail client cannot follow a relative path"
    assert_includes body, magic_session_url(token:)
  end

  def test_an_unknown_address_answers_the_same_and_sends_nothing
    assert_no_emails do
      post request_magic_session_url, params: { email_address: "nobody@example.com" }
    end

    assert_redirected_to new_session_url
    assert_equal I18n.t("shared.flash.magic_link_sent"), flash[:notice]
  end

  def test_a_valid_link_signs_in_and_burns_the_token
    post request_magic_session_url, params: { email_address: @user.email_address }
    token = @user.reload.magic_link_token

    get magic_session_url(token:)
    assert_response :redirect
    refute_equal new_session_url, response.location, "a good link must not bounce to sign-in"
    assert_nil @user.reload.magic_link_token, "the token is single use"
  end

  def test_replaying_a_used_link_is_refused
    post request_magic_session_url, params: { email_address: @user.email_address }
    token = @user.reload.magic_link_token
    get magic_session_url(token:)
    delete session_url

    get magic_session_url(token:)
    assert_redirected_to new_session_url
    assert_equal I18n.t("shared.flash.magic_link_invalid"), flash[:alert]
  end

  def test_an_expired_link_is_refused
    post request_magic_session_url, params: { email_address: @user.email_address }
    token = @user.reload.magic_link_token
    @user.update_column(:magic_link_expires_at, 1.minute.ago)

    get magic_session_url(token:)
    assert_redirected_to new_session_url
    assert_equal I18n.t("shared.flash.magic_link_invalid"), flash[:alert]
  end

  def test_a_missing_or_empty_token_is_refused
    get magic_session_url(token: "")
    assert_redirected_to new_session_url

    get magic_session_url(token: "not-a-real-token")
    assert_redirected_to new_session_url
  end

  def test_the_sign_in_form_offers_the_link
    get new_session_url

    assert_response :success
    assert_includes response.body, I18n.t("auth.magic_link")
    assert_includes response.body, "/session/magic"
  end
end
