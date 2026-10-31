# frozen_string_literal: true

class NewsletterMailer < ApplicationMailer
  include Shared::SeoKit
  helper Shared::SeoKit

  default from: "Brgen <letters@brgen.no>"

  def edition(subscription, newsletter_edition)
    @subscription = subscription
    @edition = newsletter_edition.to_edition
    @preferences_url = email_subscription_url(subscription.token, host: mail_host, protocol: "https")
    # RFC 8058: the mail client's own unsubscribe button, which Gmail and Yahoo
    # require of bulk senders. It POSTs, so it never fires from a link scanner.
    one_click = one_click_email_subscription_url(subscription.token, host: mail_host, protocol: "https")
    headers["List-Unsubscribe"] = "<#{one_click}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    mail(
      to: subscription.email,
      subject: @edition.subject,
      template_path: "newsletter_mailer",
      template_name: "edition"
    )
  end

  private

  def mail_host
    ENV.fetch("APP_HOST", "brgen.no")
  end
end
