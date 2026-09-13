# frozen_string_literal: true

class EmailSubscriptionMailer < ApplicationMailer
  # brgen.no is the one domain with working mail (MX, SPF, DKIM); a city host
  # in From would fail alignment and land in spam, so every city sends as it.
  default from: "Brgen <letters@brgen.no>"

  def confirm(sub)
    @sub = sub
    @confirm_url = confirm_email_subscription_url(token: sub.token)
    @unsubscribe_url = email_subscription_url(token: sub.token)
    mail to: sub.email, subject: t("mailer.confirm_subscription")
  end
end
