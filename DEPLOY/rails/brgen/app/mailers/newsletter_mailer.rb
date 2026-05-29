# frozen_string_literal: true

class NewsletterMailer < ApplicationMailer
  def weekly_deals(subscription)
    @subscription = subscription
    @city = subscription.city&.capitalize || "Brgen"
    @deals = Tradedoubler.deals(limit: 6)
    @unsubscribe_url = email_subscription_url(subscription.token)
    mail(to: subscription.email, subject: "#{@city} — deals this week")
  end
end
