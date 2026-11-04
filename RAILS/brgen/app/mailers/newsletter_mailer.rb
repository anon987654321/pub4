# frozen_string_literal: true

class NewsletterMailer < ApplicationMailer
  include Shared::SeoKit
  helper Shared::SeoKit

  default from: "Brgen <letters@brgen.no>"

  # In the subscriber's own locale, and pointing at their own city's site:
  # the job runs in whatever locale and host it was started with.
  def edition(subscription, newsletter_edition)
    I18n.with_locale(subscription.locale.presence || I18n.default_locale) do
      compose_edition(subscription, newsletter_edition)
    end
  end

  private

  def compose_edition(subscription, newsletter_edition)
    @subscription = subscription
    @edition = newsletter_edition.to_edition
    host = mail_host(subscription)
    @preferences_url = email_subscription_url(subscription.token, host:, protocol: "https")
    # RFC 8058: the mail client's own unsubscribe button, which Gmail and Yahoo
    # require of bulk senders. It POSTs, so it never fires from a link scanner.
    one_click = one_click_email_subscription_url(subscription.token, host:, protocol: "https")
    headers["List-Unsubscribe"] = "<#{one_click}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    mail(to: subscription.email, subject: @edition.subject,
         template_path: "newsletter_mailer", template_name: "edition")
  end

  def mail_host(subscription)
    City.find_by(slug: subscription.city)&.domain.presence || ENV.fetch("APP_HOST", "brgen.no")
  end
end
