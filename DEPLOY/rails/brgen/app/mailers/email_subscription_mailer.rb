# frozen_string_literal: true

class EmailSubscriptionMailer < ApplicationMailer
  default from: "Brgen <letters@brgen.no>"

  def confirm(sub)
    @sub = sub
    @confirm_url = confirm_email_subscription_url(token: sub.token)
    @unsubscribe_url = email_subscription_url(token: sub.token)
    mail to: sub.email, subject: "Confirm your Brgen subscription"
  end
end
