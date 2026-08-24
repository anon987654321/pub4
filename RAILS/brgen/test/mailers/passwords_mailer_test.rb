# frozen_string_literal: true

require "test_helper"

# brgen's copies of passwords_mailer/reset.* were deleted along with amber's;
# both apps now render the engine's. Proven per app because view lookup is
# per-app — a local template anywhere would silently shadow the engine again.
class PasswordsMailerTest < ActionMailer::TestCase
  def user
    @user ||= User.create!(email_address: "reset-brgen@example.com", password: "password")
  end

  def test_reset_renders_from_the_engine_views_and_layout
    mail = PasswordsMailer.reset(user)
    html = mail.html_part || mail

    assert_equal [ "reset-brgen@example.com" ], mail.to
    assert_equal I18n.t("mailer.password_reset_subject"), mail.subject
    assert_match(/brgen\.no/, mail.from.join)
    assert_match(/password/i, html.body.to_s)
    assert_match(/x-apple-disable-message-reformatting/, html.body.to_s,
                 "expected the engine layout, not Rails' generated stub")
  end
end
