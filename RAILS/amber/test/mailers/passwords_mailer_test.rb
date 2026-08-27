# frozen_string_literal: true

require "test_helper"

# passwords_mailer/reset.* and layouts/mailer.* live in the engine rather than
# copied into every app, reachable only because Shared::Engine
# appends its view path to ActionMailer as well as ActionController. Nothing
# rendered a mailer in any suite, so that path was unproven — this proves it.
class PasswordsMailerTest < ActionMailer::TestCase
  def user
    @user ||= User.strict_loading(false).create!(
      email_address: "reset-test@example.com",
      password: "password",
    )
  end

  def test_reset_renders_both_parts_from_the_engine_views
    mail = PasswordsMailer.reset(user)

    assert_equal [ "reset-test@example.com" ], mail.to
    assert_equal I18n.t("mailer.password_reset_subject"), mail.subject
    assert_match(/brgen\.no/, mail.from.join)

    html = mail.html_part || mail
    text = mail.text_part || mail
    assert_match(/password/i, html.body.to_s)
    assert_match(/password/i, text.body.to_s)
  end

  # The app-local layout was Rails' generated stub, which shadowed the engine's
  # designed one — so amber and bsdports were sending bare emails while brgen
  # was not. Deleting the stubs is only correct if the engine layout is what
  # actually renders.
  def test_reset_uses_the_engine_mailer_layout
    html = PasswordsMailer.reset(user).html_part || PasswordsMailer.reset(user)

    assert_match(/x-apple-disable-message-reformatting/, html.body.to_s,
                 "expected the engine layout, not Rails' generated stub")
  end
end
