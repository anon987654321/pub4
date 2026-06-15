# frozen_string_literal: true

class PaywallController < ApplicationController
  before_action :require_authentication

  def checkout
    blog = Blog.find_by!(slug: params[:blog_id])
    result = StripeCheckoutService.create_session(
      blog:,
      user: Current.user,
      success_url: blog_url(blog),
      cancel_url: blog_url(blog)
    )
    redirect_to blog_path(blog), notice: "Subscription activated (demo checkout #{result[:session_id]})"
  end
end