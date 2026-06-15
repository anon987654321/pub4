# frozen_string_literal: true

class NewsletterSubscriptionsController < ApplicationController
  def create
    blog = Blog.find_by!(slug: params[:blog_id])
    sub = blog.newsletter_subscriptions.find_or_initialize_by(email: params[:email].to_s.downcase.strip)
    sub.active = true
    sub.save!
    NewsletterMailer.confirm(sub).deliver_later
    redirect_to blog_path(blog), notice: "Subscribed — check your email to confirm"
  end

  def destroy
    sub = NewsletterSubscription.find_by!(token: params[:token])
    sub.update!(active: false)
    redirect_to blog_path(sub.blog), notice: "Unsubscribed"
  end

  def confirm
    sub = NewsletterSubscription.find_by!(token: params[:token])
    sub.confirm!
    redirect_to blog_path(sub.blog), notice: "Subscription confirmed"
  end
end