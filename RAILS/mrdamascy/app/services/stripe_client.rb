# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
require "openssl"

# Stripe Checkout client — the operator-mandated second payment lane, next to
# VippsClient. Same shape, same honesty rules, Net::HTTP only (APP_SPEC §2:
# no gems beyond Rails defaults).
#
#   Stripe Checkout REST API — api.stripe.com/v1
#     POST /v1/checkout/sessions      create a hosted Checkout Session
#     GET  /v1/checkout/sessions/{id} poll the session's payment_status
#
# MOCK BY DEFAULT (ENV["STRIPE_MOCK"] != "0"): every call succeeds locally and
# never raises; the "payment" happens on our own /stripe/mock approval page —
# a stand-in for Stripe's hosted Checkout, mirroring the Vipps mock. Real mode
# (STRIPE_MOCK=0) needs STRIPE_SECRET_KEY and performs the documented calls,
# raising StripeClient::NotAvailable on wiring gaps so the checkout can say
# so honestly instead of faking success.
#
# Payment honesty: a created session reserves nothing until the customer
# completes it in Stripe's hosted page; the tracking page's poll (or the
# webhook) converges the order to captured. Money column mapping: the order
# table's generic PSP columns vipps_order_id / vipps_url (schema predates
# Stripe) carry the session id and hosted URL for either gateway.
class StripeClient
  class NotAvailable < StandardError; end

  # Checkout session payment_status values we act on. "paid" means the
  # customer completed payment (funds captured by Stripe on completion).
  PAID_ON = "paid"
  FAIL_ON = "expired"

  class << self
    # --- Payment lifecycle ---------------------------------------------------

    def init_payment(order:)
      if mock_mode?
        order.vipps_order_id = "mock-stripe-#{order.tracking_token}"
        order.vipps_url = Rails.application.routes.url_helpers.stripe_mock_url(
          token: order.tracking_token, host: default_host
        )
        order.payment_state = "authorised"
        persist_payment_columns!(order)
        true
      else
        init_real_payment!(order)
        persist_payment_columns!(order)
      end
    end

    # Same column discipline as VippsClient: update_columns so order
    # validations (address/phone) can't block a payment write.
    def persist_payment_columns!(order)
      order.update_columns(
        vipps_order_id: order.vipps_order_id,
        vipps_url: order.vipps_url,
        payment_state: order.payment_state
      )
    end

    # The reconciliation seam, mirroring VippsClient#sync_payment!: idempotent,
    # converges from either the webhook or the tracking poll, swallows
    # transport errors (the next poll/webhook retries — honest silence beats a
    # 500).
    def sync_payment!(order:)
      return order if mock_mode? || order.payment_state == "captured"
      return order unless order.vipps_order_id.present?

      remote_status = session_status(id: order.vipps_order_id)
      case remote_status
      when PAID_ON
        mark_captured(order)
      when FAIL_ON
        order.update!(payment_state: "failed") unless order.payment_state == "failed"
      end
      order
    rescue NotAvailable
      order
    end

    # Stripe captures on completion — "capture" is our own state transition.
    def mark_captured(order)
      if order.payment_state != "captured"
        attrs = { payment_state: "captured" }
        # The kitchen may already have advanced the order while the customer
        # was paying — capture confirms payment, it never rewinds the kitchen.
        attrs[:state] = "confirmed" if order.state == "placed"
        order.update!(attrs)
      end
      true
    end

    # --- Webhook signature ----------------------------------------------------

    # Stripe signs webhooks as HMAC-SHA256 over "{timestamp}.{raw_body}" with
    # the webhook signing secret; the Stripe-Signature header lists t= and
    # v1=… pairs. Constant-time compare, ±5 minute tolerance (Stripe docs).
    # Raises NotAvailable on any mismatch — callers answer 400/401.
    def verify_signature!(payload:, header:, secret:)
      raise NotAvailable, "Missing Stripe-Signature header" if header.blank?
      raise NotAvailable, "Missing STRIPE_WEBHOOK_SECRET" if secret.blank?

      timestamp = nil
      signatures = []
      header.split(",").each do |part|
        key, _, value = part.strip.partition("=")
        timestamp = value if key == "t"
        signatures << value if key == "v1"
      end
      raise NotAvailable, "Stripe-Signature had no timestamp" if timestamp.blank?

      if (Time.current.to_i - timestamp.to_i).abs > 300
        raise NotAvailable, "Stripe-Signature timestamp outside tolerance"
      end

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
      matched = signatures.any? do |sig|
        ActiveSupport::SecurityUtils.secure_compare(sig, expected)
      end
      raise NotAvailable, "Stripe signature mismatch" unless matched

      true
    end

    # --- Mode & configuration -------------------------------------------------

    def mock_mode?
      ENV["STRIPE_MOCK"] != "0"
    end

    private

    def init_real_payment!(order)
      params = {
        mode: "payment",
        success_url: Rails.application.routes.url_helpers.track_url(
          token: order.tracking_token, host: default_host
        ),
        cancel_url: Rails.application.routes.url_helpers.checkout_url(host: default_host),
        client_reference_id: reference(order),
        "metadata[tracking_token]": order.tracking_token,
        "line_items[0][quantity]": 1,
        "line_items[0][price_data][currency]": "nok",
        "line_items[0][price_data][unit_amount]": order.total_ore.to_i,
        "line_items[0][price_data][product_data][name]":
          "Mr. Damascy — bestilling #{order.tracking_token}"
      }

      body = http_post(
        "/v1/checkout/sessions",
        headers: request_headers(idempotency_key: idempotency_key(order, "init")),
        body: URI.encode_www_form(params.map { |k, v| [ k.to_s, v ] })
      )

      order.vipps_order_id = body["id"].presence
      order.vipps_url = body["url"].presence
      raise NotAvailable, "Stripe session response had no hosted url" unless order.vipps_url.present?

      true
    end

    # GET /v1/checkout/sessions/{id} → payment_status: paid | unpaid | expired
    def session_status(id:)
      body = http_get(
        "/v1/checkout/sessions/#{URI.encode_www_form_component(id)}",
        headers: request_headers
      )
      body["payment_status"].presence or
        raise NotAvailable, "Stripe session response had no payment_status"
    end

    def request_headers(idempotency_key: nil)
      headers = {
        "Authorization" => "Bearer #{env!('STRIPE_SECRET_KEY')}",
        "Content-Type" => "application/x-www-form-urlencoded",
        "Stripe-Version" => "2024-06-20"
      }
      headers["Idempotency-Key"] = idempotency_key if idempotency_key
      headers
    end

    # Same stable-reference rule as Vipps: ours, unique, URL-safe.
    def reference(order)
      "mrdamascy-#{order.tracking_token}"
    end

    def idempotency_key(order, action)
      "#{reference(order)}-#{action}"
    end

    def default_host
      host = Rails.application.routes.default_url_options[:host]
      return host if host.present?
      return "localhost:3000" unless Rails.env.production?

      raise NotAvailable, "Set Rails.application.routes.default_url_options[:host] for Stripe success_url"
    end

    # --- HTTP core (the one seam tests stub) -----------------------------------

    def env!(key)
      ENV[key].presence || raise(NotAvailable, "Missing ENV #{key} for real Stripe mode")
    end

    def api_base
      @api_base ||= (ENV["STRIPE_API_BASE"].presence || "https://api.stripe.com").delete_suffix("/")
    end

    def http_post(path, headers:, body:)
      perform_request(Net::HTTP::Post, path, headers, body)
    end

    def http_get(path, headers:)
      perform_request(Net::HTTP::Get, path, headers, nil)
    end

    def perform_request(request_class, path, headers, body)
      uri = URI.join("#{api_base}/", path.delete_prefix("/"))
      request = request_class.new(uri.request_uri)
      headers.each { |key, value| request[key] = value }
      request.body = body if body

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise NotAvailable, "Stripe API #{request_class.name.split('::').last} #{path} failed: HTTP #{response.code}"
      end

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError => e
      raise NotAvailable, "Stripe API returned non-JSON: #{e.message}"
    end
  end
end
