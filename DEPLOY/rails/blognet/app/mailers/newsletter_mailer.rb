# frozen_string_literal: true

class NewsletterMailer < ApplicationMailer
  def new_post(subscription, post)
    @subscription = subscription
    @post = post
    @blog = post.blog
    mail(to: subscription.email, subject: "New post: #{post.title}")
  end

  def confirm(subscription)
    @subscription = subscription
    mail(to: subscription.email, subject: "Confirm newsletter subscription")
  end
end