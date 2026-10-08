# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "securerandom"

module Shared
  # HMAC-signed cross-app SSO payload between MASTER web and RAILS apps.
  # Secret: MASTER_SSO_SECRET (preferred) or MASTER_INTERNAL_TOKEN.
  #
  # Single-use: every token carries a `jti` and `verify` claims it in the app's
  # cache before returning a payload. Without that, the 120-second TTL was the only
  # limit on replay (TODO.md:
  # rails_coverage_contract_is_tautological, "sso_token also has no replay/nonce
  # protection on its 120s token") — an SSO URL in a referrer header, a proxy log,
  # or shoulder-surfed off a screen was a working login for anyone holding it, as
  # many times as they liked.
  #
  # The nonce is scoped to one app's cache on purpose: the `app` claim plus
  # `expected_app` already means a brgen token cannot be consumed by amber, so a
  # per-app cache is the correct boundary and needs no shared store.
  module SsoToken
    DEFAULT_TTL = 120
    APPS = %w[brgen amber bsdports master].freeze
    NONCE_PREFIX = "shared:sso:jti"
    # Outlives the token so a claim cannot expire while the token is still valid.
    NONCE_GRACE = 60

    module_function

    def secret
      ENV["MASTER_SSO_SECRET"].to_s.strip.presence ||
        ENV["MASTER_INTERNAL_TOKEN"].to_s.strip.presence ||
        ENV["MASTER_BRIDGE_TOKEN"].to_s.strip.presence
    end

    def configured?
      secret.to_s.length >= 16
    end

    def mint(app:, email:, user_id: nil, display_name: nil, ttl: DEFAULT_TTL)
      raise ArgumentError, "SSO secret not configured" unless configured?
      raise ArgumentError, "unknown app #{app}" unless APPS.include?(app.to_s)

      payload = {
        "app" => app.to_s,
        "email" => email.to_s.downcase.strip,
        "user_id" => user_id,
        "display_name" => display_name.to_s.presence,
        "exp" => Time.now.to_i + ttl.to_i,
        "iat" => Time.now.to_i,
        "jti" => SecureRandom.uuid,
        "v" => 1,
      }
      body = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      sig = sign(body)
      "#{body}.#{sig}"
    end

    # consume: false inspects a token without spending it — for a health check or a
    # test, never for a login.
    def verify(token, expected_app: nil, consume: true)
      return nil unless configured?
      return nil if token.to_s.strip.empty?

      body, sig = token.to_s.split(".", 2)
      return nil if body.blank? || sig.blank?
      return nil unless secure_compare(sign(body), sig)

      payload = JSON.parse(Base64.urlsafe_decode64(body))
      return nil if payload["exp"].to_i < Time.now.to_i
      return nil if expected_app && payload["app"].to_s != expected_app.to_s
      return nil if payload["email"].to_s.strip.empty?
      return nil if consume && !claim_nonce(payload)

      payload
    rescue JSON::ParserError, ArgumentError
      nil
    end

    # True the first time a jti is seen, false on every replay. A token minted
    # before jti existed has none and cannot be forged without the secret, so it is
    # allowed through rather than breaking links already in flight.
    def claim_nonce(payload)
      jti = payload["jti"].to_s
      return true if jti.empty?

      key = "#{NONCE_PREFIX}:#{payload["app"]}:#{jti}"
      ttl = [ payload["exp"].to_i - Time.now.to_i, 0 ].max + NONCE_GRACE
      cache = nonce_cache
      return cache.write(key, true, unless_exist: true, expires_in: ttl) if cache

      claim_in_process(key, ttl)
    end

    # NullStore answers true to every write, which would leave the check looking
    # present and doing nothing — the failure shape this codebase keeps finding. So
    # an unusable store is named and replaced rather than trusted.
    def nonce_cache
      return nil unless defined?(Rails) && Rails.respond_to?(:cache)

      cache = Rails.cache
      return nil if cache.nil? ||
                    (defined?(ActiveSupport::Cache::NullStore) && cache.is_a?(ActiveSupport::Cache::NullStore))

      cache
    end

    # Process-local fallback. It cannot see a replay that lands on another Falcon
    # worker, which is why the real store is preferred — but it does catch the
    # single-process case, and it means this guard is never merely decorative.
    @seen_nonces = {}
    @nonce_mutex = Mutex.new

    def claim_in_process(key, ttl)
      now = Time.now.to_i
      @nonce_mutex.synchronize do
        @seen_nonces.delete_if { |_, expires_at| expires_at <= now }
        next false if @seen_nonces.key?(key)

        @seen_nonces[key] = now + ttl
        true
      end
    end

    def sign(body)
      OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    end

    def secure_compare(a, b)
      return false if a.bytesize != b.bytesize

      ActiveSupport::SecurityUtils.secure_compare(a, b)
    rescue StandardError # scan: intentional — a malformed token compares unequal — fail closed
      false
    end
  end
end
