# frozen_string_literal: true

require "test_helper"

# Every brgen mailer's subject resolves through I18n, and both parts of a
# multipart mail carry the link the reader has to click.
class BrgenMailersTest < ActionMailer::TestCase
  include Rails.application.routes.url_helpers
  test "subscription confirmation subject is a key and both parts carry the token" do
    sub = EmailSubscription.create!(email: "letters-test@example.com")
    mail = EmailSubscriptionMailer.confirm(sub)

    assert_equal I18n.t("mailer.confirm_subscription"), mail.subject
    assert_equal [ "letters-test@example.com" ], mail.to
    assert_match(/brgen\.no/, mail.from.join)
    preference_path = email_subscription_path(token: sub.token)
    assert mail.html_part, "expected an html part"
    assert mail.text_part, "expected a text part"
    [ mail.html_part, mail.text_part ].each do |part|
      assert_includes part.body.to_s, sub.token
      assert_includes part.body.to_s, I18n.t("mailer.confirm_lede")
      assert_includes part.body.to_s, preference_path
    end
  end

  test "newsletter carries a real preferences link in both parts" do
    sub = EmailSubscription.create!(
      email: "newsletter-preferences@example.com",
      confirmed: true,
      agreed_to_marketing: true
    )
    edition = NewsletterEdition.create!(
      kind: "daily",
      city: "bergen",
      edition_date: Date.current,
      subject: "Bergen today",
      lede: "A few useful things.",
      sign_off: "Brgen",
      permission_line: "You asked for these emails.",
      stories: [],
      deals: []
    )

    mail = NewsletterMailer.edition(sub, edition)
    preference_path = email_subscription_path(token: sub.token)

    [ mail.html_part, mail.text_part ].each do |part|
      assert_includes part.body.to_s, preference_path
      assert_includes part.body.to_s, I18n.t("email_preferences.title")
    end
  end

  test "verification subject is a key and both parts carry the token" do
    user = User.create!(email_address: "verify-brgen@example.com", password: "password")
    token = user.generate_email_verification!
    mail = VerificationMailer.verify(user.reload)

    assert_equal I18n.t("mailer.verify_email_subject"), mail.subject
    [ mail.html_part, mail.text_part ].each do |part|
      assert_includes part.body.to_s, token
      assert_includes part.body.to_s, I18n.t("mailer.verify_welcome")
    end
  end

  test "queue failure digest subject is a key" do
    mail = QueueFailureMailer.daily_digest("SomeJob bulk 3", to: "ops@example.com")

    assert_equal I18n.t("mailer.queue_failure_digest_subject"), mail.subject
    assert_includes mail.body.to_s, "SomeJob bulk 3"
  end
end
