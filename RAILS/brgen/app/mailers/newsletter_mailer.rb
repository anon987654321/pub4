# frozen_string_literal: true

class NewsletterMailer < ApplicationMailer
  include Shared::SeoKit
  helper Shared::SeoKit

  default from: "Brgen <letters@brgen.no>"

  def edition(subscription, newsletter_edition)
    @subscription = subscription
    @edition = newsletter_edition.to_edition
    @unsubscribe_url = email_subscription_url(subscription.token, host: mail_host)
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
