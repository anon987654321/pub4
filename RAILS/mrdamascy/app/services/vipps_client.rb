# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
require "base64"

# Vipps client — the whole "fewer steps than Foodora" engine (APP_SPEC §5/§12).
#
# Two documented Vipps APIs, one client, Net::HTTP only (no gems, APP_SPEC §2):
#
#   ePayment API v1 — api.vipps.no/epayment/v1
#     POST /epayment/v1/payments                 create (WEB_REDIRECT → wallet)
#     GET  /epayment/v1/payments/{reference}     poll the payment's state
#     POST /epayment/v1/payments/{reference}/capture
#     POST /accesstoken/get                      Bearer token, cached in-process
#
#   Login API (OAuth2) — api.vipps.no/access-management-1.0
#     GET  /access/oauth2/auth                   "Logg inn med Vipps"
#     POST /access/oauth2/token                  code → access token
#     GET  /access/userinfo                      verified name/phone/address
#
# MOCK BY DEFAULT (ENV["VIPPS_MOCK"] != "0"): every call succeeds locally and
# never raises; the "payment" happens on our own /vipps/mock approval page and
# the "login" on /vipps/login_mock — dev/test stand-ins for the Vipps app.
#
# REAL MODE (VIPPS_MOCK=0) performs the documented HTTP calls and raises
# VippsClient::NotAvailable when credentials are missing or Vipps answers with
# an error. Guarded behind mock_mode?, so mock users never touch the network.
#
# Payment honesty: init reserves, nothing captures until Vipps says
# AUTHORIZED — via the webhook (POST /vipps/callback, secret-verified) or the
# tracking page's poll sync. Both paths funnel into sync_payment!/capture.
class VippsClient
  # Raised for real-mode wiring gaps (missing ENV, HTTP error, bad payload).
  class NotAvailable < StandardError; end

  # ePayment states → what we do with them (APP_SPEC §5). Capture is
  # immediate: food is made to be eaten, and Foodora captures at placement too.
  CAPTURE_ON = "AUTHORIZED"
  FAIL_ON = %w[ABORTED EXPIRED TERMINATED].freeze

  class << self
    # Guards the access-token cache — one token fetch per process, not one
    # per concurrent request. A plain mutex (Mutex_m's initialize hook never
    # runs on a singleton class, so its lazily-created ivar is a trap).
    TOKEN_MUTEX = Thread::Mutex.new

    # --- Payment lifecycle ---------------------------------------------------

    # Reserve ("initiate") a payment for the order: fills vipps_order_id
    # (the ePayment reference) and vipps_url, returns true.
    #
    # Mock mode points the order at our own approval page keyed by the
    # tracking token and reports the payment authorised — the mock page's
    # approve step then completes it.
    #
    # Real mode keeps payment_state "pending": money is reserved only when the
    # customer approves in the Vipps app, and capture happens on AUTHORIZED
    # (webhook or tracking-poll sync) — never on a maybe.
    def init_payment(order:)
      if mock_mode?
        order.vipps_order_id = "mock-#{order.tracking_token}"
        order.vipps_url = Rails.application.routes.url_helpers.vipps_mock_url(
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

    # Persist exactly the payment columns the client owns. update_columns, not
    # save!: the order's own validations (address, phone, …) are the checkout's
    # business, and a defensively blank phone must not block a payment write.
    def persist_payment_columns!(order)
      order.update_columns(
        vipps_order_id: order.vipps_order_id,
        vipps_url: order.vipps_url,
        payment_state: order.payment_state
      )
    end

    # The single reconciliation seam: move our order to what Vipps says about
    # its payment. Idempotent across page load, 10 s poll and webhook (capture
    # carries an Idempotency-Key). Mock mode: the mock approve action captures.
    # A cancelled order is never captured, as its food will not be made. This
    # client has no cancel call, so the reservation is kept as authorised and
    # Order#owe_manual_refund flags it manual_due for staff to void by hand.
    def sync_payment!(order:)
      return order if mock_mode? || order.payment_state == "captured"
      return order unless order.vipps_order_id.present?

      remote_state = payment_state(reference: order.vipps_order_id)
      case remote_state
      when CAPTURE_ON
        order.state == "cancelled" ? order.update!(payment_state: "authorised") : capture_payment(order:)
      when *FAIL_ON
        order.update!(payment_state: "failed") unless order.payment_state == "failed"
      end
      order
    rescue NotAvailable
      # Poll/webhook must never crash the page: the next poll or webhook
      # retry will reconcile. Honest silence beats a 500.
      order
    end

    # Capture a reserved payment and confirm the order (AUTHORIZED →
    # captured + confirmed). Mock: no-op success. Real: POST capture with
    # modificationAmount and a stable Idempotency-Key; "already captured"
    # answers count as success so replays converge.
    def capture_payment(order:)
      return true if mock_mode?

      body = {
        modificationAmount: { currency: "NOK", value: order.total_ore.to_i }
      }.to_json
      http_post(
        "/epayment/v1/payments/#{URI.encode_www_form_component(order.vipps_order_id)}/capture",
        headers: payment_headers(idempotency_key: idempotency_key(order, "capture")),
        body: body
      )
      if order.payment_state != "captured"
        attrs = { payment_state: "captured" }
        # The kitchen may already have advanced the order while Vipps was
        # authorising — capture confirms payment, it never rewinds the kitchen.
        attrs[:state] = "confirmed" if order.state == "placed"
        order.update!(attrs)
      end
      true
    end

    # --- Login ("Logg inn med Vipps") ----------------------------------------

    # Build the OAuth2 authorize URL the visitor is bounced to. Scopes give us
    # verified phone + name + address — the reason a Vipps user never types a
    # checkout form here (Foodora makes you type all three, every time).
    def login_authorize_url(redirect_uri:, state:, nonce:)
      scopes = %w[openid email phoneNumber address]
      params = {
        client_id: login_env("VIPPS_CLIENT_ID"),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: scopes.join(" "),
        state: state,
        nonce: nonce
      }
      "#{login_base}/access-management-1.0/access/oauth2/auth?#{params.to_query}"
    end

    # Exchange the ?code= for tokens (form-encoded, HTTP Basic client auth).
    # Returns the raw token hash (access_token, id_token, expires_in, …).
    def exchange_login_code!(code:, redirect_uri:)
      headers = {
        "Content-Type" => "application/x-www-form-urlencoded",
        "Authorization" => "Basic #{Base64.strict_encode64("#{login_env('VIPPS_CLIENT_ID')}:#{login_env('VIPPS_CLIENT_SECRET')}")}"
      }
      body = {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri
      }.to_query
      parsed = http_post("/access-management-1.0/access/oauth2/token", headers: headers, body: body)
      parsed["access_token"].presence or raise NotAvailable, "Vipps Login token response had no access_token"
      parsed
    end

    # Fetch the verified profile: { sub:, name:, phone_number:, email:,
    # address: { formatted, street_address, postal_code, … } }.
    def login_userinfo!(access_token:)
      http_get(
        "/access-management-1.0/access/userinfo",
        headers: { "Authorization" => "Bearer #{access_token}" }
      )
    end

    # --- Mode & configuration -------------------------------------------------

    # Vipps Login userinfo returns "4790000004"; our users live as 8-digit
    # Norwegian locals (SessionsController + OTP do the same). Normalising
    # here keeps "one identity per phone" — the 47-prefixed Vipps profile
    # and the OTP-typed number resolve to the same customer row.
    def login_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits = digits[2..] if digits.match?(/\A47\d{8}\z/)
      digits.presence
    end

    def mock_mode?
      ENV["VIPPS_MOCK"] != "0"
    end

    private

    # --- Real payment plumbing -----------------------------------------------

    def init_real_payment!(order)
      payload = {
        amount: { value: order.total_ore.to_i, currency: "NOK" },
        paymentMethod: { type: "WALLET" },
        reference: epayment_reference(order),
        returnUrl: Rails.application.routes.url_helpers.track_url(
          token: order.tracking_token, host: default_host
        ),
        userFlow: "WEB_REDIRECT",
        paymentDescription: "Mr. Damascy #{order.tracking_token}"
      }
      # Verified phone lets Vipps preselect the customer's wallet — the tap
      # count in the Vipps app goes from "find yourself" to "fingerprint".
      if (phone = vipps_phone(order.phone))
        payload[:customer] = { phoneNumber: phone }
      end

      body = http_post(
        "/epayment/v1/payments",
        headers: payment_headers(idempotency_key: idempotency_key(order, "init")),
        body: payload.to_json
      )

      order.vipps_order_id = body["reference"] || epayment_reference(order)
      order.vipps_url = body["paymentRedirectUrl"].presence || body["redirectUrl"].presence
      raise NotAvailable, "Vipps init response had no redirect URL" unless order.vipps_url.present?

      true
    end

    # GET /epayment/v1/payments/{reference} → "state": CREATED | AUTHORIZED |
    # ABORTED | EXPIRED | TERMINATED (capture shows in aggregate, not state).
    def payment_state(reference:)
      body = http_get(
        "/epayment/v1/payments/#{URI.encode_www_form_component(reference)}",
        headers: payment_headers
      )
      body["state"].presence or raise NotAvailable, "Vipps payment state response had no state"
    end

    def payment_headers(idempotency_key: nil)
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{access_token}",
        "Ocp-Apim-Subscription-Key" => env!("VIPPS_SUBSCRIPTION_KEY"),
        "Merchant-Serial-Number" => env!("VIPPS_MSN"),
        "Vipps-System-Name" => "mrdamascy",
        "Vipps-System-Version" => "1.0.0"
      }
      headers["Idempotency-Key"] = idempotency_key if idempotency_key
      headers
    end

    # ePayment reference: stable, unique, ours (max ~50 chars, URL-safe).
    def epayment_reference(order)
      "mrdamascy-#{order.tracking_token}"
    end

    def idempotency_key(order, action)
      "#{epayment_reference(order)}-#{action}"
    end

    # Vipps wants 8-digit numbers with the 47 country code ("4790000004").
    def vipps_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      return nil unless digits.match?(/\A\d{8}\z/) || digits.match?(/\A47\d{8}\z/)

      digits.start_with?("47") ? digits : "47#{digits}"
    end

    # --- Access token (cached in-process, mutex-guarded) ----------------------

    TOKEN_SLACK = 120 # seconds before real expiry we consider the token stale

    def access_token
      TOKEN_MUTEX.synchronize do
        return @access_token if defined?(@access_token) && @access_token &&
                                @access_token_expires_at && Time.current < @access_token_expires_at

        body = http_post("/accesstoken/get", headers: {
          "Content-Type" => "application/json",
          "client_id" => env!("VIPPS_CLIENT_ID"),
          "client_secret" => env!("VIPPS_CLIENT_SECRET"),
          "Ocp-Apim-Subscription-Key" => env!("VIPPS_SUBSCRIPTION_KEY"),
          "Merchant-Serial-Number" => env!("VIPPS_MSN")
        }, body: "{}")

        @access_token = body["access_token"].presence or
                        raise NotAvailable, "Vipps accesstoken response had no access_token"
        @access_token_expires_at = Time.current +
                                   body["expires_in"].to_i.seconds - TOKEN_SLACK.seconds
        @access_token
      end
    end

    # --- Login plumbing --------------------------------------------------------

    def login_base
      api_base
    end

    def login_env(key)
      env!(key)
    end

    # --- HTTP core (the one seam tests stub) -----------------------------------

    def api_base
      @api_base ||= (ENV["VIPPS_API_BASE"].presence || "https://api.vipps.no").delete_suffix("/")
    end

    def default_host
      host = Rails.application.routes.default_url_options[:host]
      return host if host.present?
      return "localhost:3000" unless Rails.env.production?

      # A returnUrl of localhost in production would strand the customer
      # outside the PWA after paying — refuse loudly instead.
      raise NotAvailable, "Set Rails.application.routes.default_url_options[:host] for Vipps returnUrl"
    end

    def env!(key)
      ENV[key].presence || raise(NotAvailable, "Missing ENV #{key} for real Vipps mode")
    end

    # POST JSON (or form) and parse the JSON answer. 422 "already captured"
    # on capture is a success for our purposes — handled by the caller's
    # idempotency, so only network/5xx/4xx-others raise.
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
        raise NotAvailable, "Vipps API #{request_class.name.split('::').last} #{path} failed: HTTP #{response.code}"
      end

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError => e
      raise NotAvailable, "Vipps API returned non-JSON: #{e.message}"
    end
  end
end
