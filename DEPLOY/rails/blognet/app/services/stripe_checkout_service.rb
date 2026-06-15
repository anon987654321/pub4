# frozen_string_literal: true

class StripeCheckoutService
  def self.create_session(blog:, user:, success_url:, cancel_url:)
    return demo_session(blog, user) unless stripe_configured?

    # Real Stripe integration hook — requires stripe gem + API keys in production
    demo_session(blog, user)
  end

  def self.demo_session(blog, user)
    sub = Subscription.find_or_create_by!(blog:, user:) do |s|
      s.status = "active"
      s.expires_at = 30.days.from_now
      s.stripe_checkout_session_id = "demo_#{SecureRandom.hex(8)}"
    end
    { session_id: sub.stripe_checkout_session_id, subscription: sub }
  end

  def self.stripe_configured?
    ENV["STRIPE_SECRET_KEY"].present?
  end
end