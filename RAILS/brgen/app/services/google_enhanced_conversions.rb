# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"
require "time"

# Server-side enhanced / offline click conversions for Google Ads.
#
# As of 2026-06-15, new adopters must use the Data Manager API
# (POST https://datamanager.googleapis.com/v1/events:ingest).
# Google Ads API ConversionUploadService.UploadClickConversions is allowlist-only
# for existing importers.
#
# Flow:
#   1. Marketplace order becomes paid (Stripe/Vipps webhook or mark_paid!)
#   2. Job calls GoogleEnhancedConversions.upload_purchase!(order)
#   3. Event carries transactionId, value, currency, optional gclid,
#      and SHA-256 hashed email/phone for enhanced matching
#
# ENV:
#   GOOGLE_ADS_CUSTOMER_ID              — 10-digit Ads customer id (no dashes)
#   GOOGLE_ADS_CONVERSION_ACTION_ID     — UPLOAD_CLICKS conversion action id
#   GOOGLE_ADS_ACCESS_TOKEN             — OAuth Bearer with Data Manager + Ads access
#   GOOGLE_ENHANCED_CONVERSIONS=1      — feature flag (off by default)
#
# Optional:
#   GOOGLE_ADS_LOGIN_CUSTOMER_ID        — MCC id if using a manager account
module GoogleEnhancedConversions
  INGEST_URL = "https://datamanager.googleapis.com/v1/events:ingest"
  NotConfigured = Class.new(StandardError)
  ApiError = Class.new(StandardError)

  class << self
    def enabled?
      %w[1 true yes on].include?(ENV["GOOGLE_ENHANCED_CONVERSIONS"].to_s.strip.downcase)
    end

    def customer_id = ENV["GOOGLE_ADS_CUSTOMER_ID"].to_s.gsub(/\D/, "").presence
    def conversion_action_id = ENV["GOOGLE_ADS_CONVERSION_ACTION_ID"].to_s.strip.presence
    def access_token = ENV["GOOGLE_ADS_ACCESS_TOKEN"].to_s.strip.presence
    def login_customer_id = ENV["GOOGLE_ADS_LOGIN_CUSTOMER_ID"].to_s.gsub(/\D/, "").presence

    def configured?
      enabled? && customer_id.present? && conversion_action_id.present? && access_token.present?
    end

    # Primary entry from payment success.
    #
    # order must respond to:
    #   id, paid_at (or created_at), total (Float or cents via total_cents),
    #   currency (optional, default NOK)
    # optional: gclid, email, phone, ad_user_data_consent (true/false),
    #           line_items (array of { offer_id:, unit_price:, quantity: })
    def upload_purchase!(order, validate_only: false)
      raise NotConfigured, "Google enhanced conversions" unless configured?

      event = build_event(order)
      ingest!(events: [ event ], validate_only: validate_only)
    end

    def build_event(order)
      paid_at = order.try(:paid_at) || order.try(:created_at) || Time.current
      value = order_value(order)
      currency = (order.try(:currency).presence || "NOK").to_s.upcase

      event = {
        "transactionId" => order.id.to_s,
        "eventSource" => "WEB",
        "eventTimestamp" => paid_at.utc.iso8601,
        "conversionValue" => value,
        "currency" => currency
      }

      gclid = order.try(:gclid).presence
      event["adIdentifiers"] = { "gclid" => gclid } if gclid

      # consent_for already refuses to claim consent it does not have. The same
      # rule has to reach the data, not only the flag: a hashed email is still
      # the customer's, and it is uploaded whether or not a consent block rides
      # along. No order carries ad_user_data_consent today, so unknown is every
      # order, and sending under it would mean sending for all of them.
      consent = consent_for(order)
      event["consent"] = consent if consent

      # Granted, not merely known: consent_for returns a block for a denial too,
      # so testing the block sends the customer's details on the one answer that
      # most clearly refuses them.
      identifiers = order.try(:ad_user_data_consent) == true ? user_identifiers_for(order) : []
      if identifiers.any?
        event["userData"] = {
          "userIdentifiers" => identifiers
        }
      end

      cart = cart_data_for(order)
      event["cartData"] = cart if cart

      event
    end

    # --- Hashing (Google rules) ------------------------------------------------

    def normalize_and_hash(str)
      Digest::SHA256.hexdigest(str.to_s.strip.downcase)
    end

    # Gmail: strip dots in local part before hash.
    def normalize_and_hash_email(email)
      raw = email.to_s.strip.downcase
      return nil if raw.empty?

      local, domain = raw.split("@", 2)
      return normalize_and_hash(raw) if domain.nil?

      if domain.match?(/\A(gmail|googlemail)\.com\z/)
        local = local.delete(".")
      end
      normalize_and_hash("#{local}@#{domain}")
    end

    # E.164-ish: keep leading +, digits only after strip.
    def normalize_and_hash_phone(phone)
      raw = phone.to_s.strip
      return nil if raw.empty?

      digits = raw.gsub(/[^\d+]/, "")
      digits = digits.sub(/\A\+/, "") # Google examples often hash digits-only; keep consistent
      # Prefer E.164 without spaces: if Norwegian local 8-digit, caller should pass +47…
      normalize_and_hash(digits)
    end

    private

    def order_value(order)
      if order.respond_to?(:total_cents) && order.total_cents
        order.total_cents.to_i / 100.0
      elsif order.respond_to?(:total)
        order.total.to_f
      else
        0.0
      end
    end

    def user_identifiers_for(order)
      ids = []
      email = order.try(:email).presence || order.try(:buyer_email).presence
      phone = order.try(:phone).presence || order.try(:buyer_phone).presence

      if (hashed = normalize_and_hash_email(email))
        ids << { "hashedEmail" => hashed }
      end
      if (hashed = normalize_and_hash_phone(phone))
        ids << { "hashedPhoneNumber" => hashed }
      end
      ids.first(5)
    end

    def cart_data_for(order)
      items = order.try(:line_items) || order.try(:items)
      return nil if items.blank?

      {
        "items" => Array(items).filter_map do |item|
          offer = item.try(:offer_id) || item.try(:[], :offer_id) ||
                  (item.try(:listing_id) ? "brgen-#{item.listing_id}" : nil)
          next if offer.blank?

          {
            "itemId" => offer.to_s,
            "unitPrice" => (item.try(:unit_price) || item.try(:[], :unit_price) || item.try(:price)).to_f,
            "quantity" => (item.try(:quantity) || item.try(:[], :quantity) || 1).to_i
          }
        end
      }.tap { |h| return nil if h["items"].empty? }
    end

    def consent_for(order)
      # Only send when we know. Missing consent ≠ granted.
      granted = order.try(:ad_user_data_consent)
      return nil if granted.nil?

      status = granted ? "CONSENT_GRANTED" : "CONSENT_DENIED"
      {
        "adUserData" => status,
        "adPersonalization" => status
      }
    end

    def ingest!(events:, validate_only: false)
      body = {
        "destinations" => [
          {
            "operatingAccount" => {
              "accountType" => "GOOGLE_ADS",
              "accountId" => customer_id
            },
            "productDestinationId" => conversion_action_id
          }
        ],
        "encoding" => "HEX",
        "events" => events,
        "validateOnly" => validate_only
      }

      # Some Data Manager setups use GOOGLE_ADS_ACCOUNT as accountType string;
      # if ingest rejects GOOGLE_ADS, try GOOGLE_ADS_ACCOUNT via ENV override.
      if ENV["GOOGLE_ADS_ACCOUNT_TYPE"].present?
        body["destinations"][0]["operatingAccount"]["accountType"] = ENV["GOOGLE_ADS_ACCOUNT_TYPE"]
      end

      uri = URI(INGEST_URL)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"] = "application/json"
      req["login-customer-id"] = login_customer_id if login_customer_id
      req.body = JSON.generate(body)

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(req)
      end

      parsed = res.body.to_s.empty? ? {} : JSON.parse(res.body)
      unless res.is_a?(Net::HTTPSuccess)
        msg = parsed.dig("error", "message") || parsed["message"] || res.code
        raise ApiError, "Data Manager ingest: #{msg}"
      end
      parsed
    end
  end
end
