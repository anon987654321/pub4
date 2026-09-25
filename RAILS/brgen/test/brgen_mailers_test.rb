# frozen_string_literal: true

require "test_helper"

# Every brgen mailer's subject resolves through I18n, and both parts of a
# multipart mail carry the link the reader has to click.
class BrgenMailersTest < ActionMailer::TestCase
  test "subscription confirmation subject is a key and both parts carry the token" do
    sub = EmailSubscription.create!(email: "letters-test@example.com")
    mail = EmailSubscriptionMailer.confirm(sub)

    assert_equal I18n.t("mailer.confirm_subscription"), mail.subject
    assert_equal [ "letters-test@example.com" ], mail.to
    assert_match(/brgen\.no/, mail.from.join)
    assert mail.html_part, "expected an html part"
    assert mail.text_part, "expected a text part"
    [ mail.html_part, mail.text_part ].each do |part|
      assert_includes part.body.to_s, sub.token
      assert_includes part.body.to_s, I18n.t("mailer.confirm_lede")
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
