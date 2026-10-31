# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Shared
  # Recurring billing through Stripe: a Checkout Session in subscription mode to
  # start a plan, the customer portal to change or cancel it, and the webhook
  # events that keep Shared::BillingSubscription in step. Stripe holds the card
  # and the invoices; nothing here stores either.
  #
  # A plan is not sellable until both API credentials are present: the secret key
  # starts checkout, while the webhook signing secret is what makes successful
  # payments grant entitlements. Enabling checkout without the latter would take
  # money while leaving the subscriber locked out.
  module StripeBilling
    API = "https://api.stripe.com/v1"
    SUBSCRIPTION_EVENTS = %w[customer.subscription.created customer.subscription.updated
                             customer.subscription.deleted].freeze

    class Error < StandardError; end

    module_function

    def configured?
      ENV["STRIPE_SECRET_KEY"].to_s.strip.present? &&
        ENV["STRIPE_WEBHOOK_SECRET"].to_s.strip.present?
    end

    # Where to send the reader to subscribe to +plan+.
    def checkout_url(user:, plan:, success_url:, cancel_url:)
      raise Error, "#{plan.key} is not available" unless plan.available?

      form = {
        "mode" => "subscription", "success_url" => success_url, "cancel_url" => cancel_url,
        "line_items[0][price]" => plan.price_id, "line_items[0][quantity]" => 1,
        "client_reference_id" => "user:#{user.id}", "allow_promotion_codes" => "true",
        "subscription_data[metadata][plan]" => plan.key, "subscription_data[metadata][user_id]" => user.id.to_s,
      }
      customer = user.stripe_customer_id
      customer ? form["customer"] = customer : form["customer_email"] = user.email_address
      post("/checkout/sessions", form).fetch("url")
    end

    # Stripe's own page for changing card, plan or cancelling.
    def portal_url(user:, return_url:)
      customer = user.stripe_customer_id or raise Error, "no Stripe customer yet"

      post("/billing_portal/sessions", { "customer" => customer, "return_url" => return_url }).fetch("url")
    end

    # Applies a verified webhook event; true when it was a subscription event.
    def handle(event)
      return false unless SUBSCRIPTION_EVENTS.include?(event["type"].to_s)

      sync!(event.dig("data", "object") || {})
      true
    end

    # One row per Stripe subscription, written from what Stripe sent. A replayed
    # or late event rewrites the same row, never a second one.
    def sync!(object)
      metadata = object["metadata"] || {}
      user = ::User.find_by(id: metadata["user_id"])
      return unless user && Shared::BillingPlan.find(metadata["plan"])

      row = Shared::BillingSubscription.find_or_initialize_by(stripe_subscription_id: object.fetch("id"))
      row.update!(user:, plan_key: metadata["plan"], status: object["status"].to_s,
                  stripe_customer_id: object["customer"], cancel_at_period_end: object["cancel_at_period_end"] == true,
                  current_period_end: period_end(object))
    end

    # Stripe moved current_period_end onto the subscription item in its
    # 2025 API versions; read either.
    def period_end(object)
      seconds = object["current_period_end"] || object.dig("items", "data", 0, "current_period_end")
      Time.zone.at(seconds) if seconds
    end

    def post(path, form)
      uri = URI("#{API}#{path}")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(ENV.fetch("STRIPE_SECRET_KEY"), "")
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(form)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) do |http|
        http.request(request)
      end
      parse!(response)
    end

    def parse!(response)
      data = JSON.parse(response.body)
      return data if response.is_a?(Net::HTTPSuccess)

      raise Error, "Stripe: #{data.dig("error", "message") || response.code}"
    rescue JSON::ParserError
      raise Error, "Stripe: #{response.code}"
    end
  end
end
