# frozen_string_literal: true

class NewsletterMailer < ApplicationMailer
  def daily_digest(subscription)
    @subscription = subscription
    @city = subscription.city&.capitalize || "Brgen"
    @posts = Post.hot.includes(:user, :community).limit(6)
    @unsubscribe_url = email_subscription_url(subscription.token)
    mail(to: subscription.email, subject: "#{@city} — daily digest")
  end

  def weekly_deals(subscription)
    @subscription = subscription
    @city = subscription.city&.capitalize || "Brgen"
    @deals = Tradedoubler.deals(limit: 6)
    @unsubscribe_url = email_subscription_url(subscription.token)
    mail(to: subscription.email, subject: "#{@city} — deals this week")
  end
end
