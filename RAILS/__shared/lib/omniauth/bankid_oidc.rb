# frozen_string_literal: true
require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "rack/utils"
require "socket"
require "timeout"
require "uri"
require "jwt"

module Shared
  module BankidOIDC
    class InvalidToken < StandardError; end
    ENVIRONMENTS = {
      "production" => { issuer: "https://auth.bankid.no/auth/realms/prod", host: "auth.bankid.no",
        root_sha256: "7a58b1482120002ec8db8044205d0c7710b27c347d54313547a4eea79b48de9f" }.freeze,
      "current" => { issuer: "https://auth.current.bankid.no/auth/realms/current", host: "auth.current.bankid.no",
        root_sha256: "4d261886f081aeaa6bad59008bf2e9bf93053077a6256aaafa0e855fc3a76468" }.freeze,
    }.freeze
    CACHE_TTL = 3600
    JSON_LIMIT = 1_000_000
    CLOCK_SKEW = 60
    HIGH_ASSURANCE_ACR = ["urn:bankid:bid;LOA=4"].freeze
    @cache = {}
    @cache_mutex = Mutex.new

    class << self
      def clear_cache! = @cache_mutex.synchronize { @cache.clear }

      def configuration(environment)
        env = environment_config(environment)
        cache_fetch("configuration:#{environment}") do
          doc = fetch_json("#{env.fetch(:issuer)}/.well-known/openid-configuration", environment)
          raise InvalidToken, "BankID issuer mismatch" unless doc["issuer"] == env.fetch(:issuer)
          %w[authorization_endpoint token_endpoint jwks_uri].each { |key| validate_endpoint!(doc.fetch(key), environment) }
          raise InvalidToken, "BankID does not advertise ES256" unless Array(doc["id_token_signing_alg_values_supported"]).include?("ES256")
          doc
        end
      rescue KeyError, URI::InvalidURIError, JSON::ParserError => error
        raise InvalidToken, "BankID discovery invalid: #{error.class}"
      end

      def verify_id_token!(token, environment:, client_id:, nonce:, discovery: nil, jwks: nil, now: Time.now.to_i)
        raise InvalidToken, "BankID ID token missing" if token.to_s.empty?
        raise InvalidToken, "BankID nonce missing from session" if nonce.to_s.empty?
        config = discovery || configuration(environment)
        _payload, header = JWT.decode(token, nil, false)
        raise InvalidToken, "BankID algorithm must be ES256" unless header["alg"] == "ES256"
        raise InvalidToken, "BankID key id missing" if header["kid"].to_s.empty?
        key_set = jwks || signing_keys(environment, config)
        key = find_signing_key(key_set, header, environment)
        payload, = JWT.decode(token, key, true, { algorithms: ["ES256"] })
        validate_claims!(payload, config, client_id, nonce, now)
        payload
      rescue InvalidToken
        raise
      rescue StandardError => error
        raise InvalidToken, "BankID ID token rejected: #{error.class}"
      end

      def trusted_root_fingerprint(environment)
        environment_config(environment).fetch(:root_sha256)
      end

      private

      def environment_config(environment)
        ENVIRONMENTS.fetch(environment.to_s) { raise InvalidToken, "Unsupported BankID environment" }
      end

      def cache_fetch(key)
        @cache_mutex.synchronize do
          row = @cache[key]
          return row[:value] if row && row[:expires_at] > Time.now.to_f
          value = yield
          @cache[key] = { value:, expires_at: Time.now.to_f + CACHE_TTL }
          value
        end
      end

      def fetch_json(url, environment)
        uri = validate_endpoint!(url, environment)
        request = Net::HTTP::Get.new(uri.request_uri)
        response = Net::HTTP.start(
          uri.host, uri.port, use_ssl: true,
          open_timeout: 5, read_timeout: 8, write_timeout: 5,
          verify_mode: OpenSSL::SSL::VERIFY_PEER
        ) { |http| http.request(request) }
        raise InvalidToken, "BankID metadata request failed" unless response.is_a?(Net::HTTPSuccess)
        raise InvalidToken, "BankID response too large" if response.body.to_s.bytesize > JSON_LIMIT
        JSON.parse(response.body)
      rescue Timeout::Error, SocketError, SystemCallError => error
        raise InvalidToken, "BankID metadata unavailable: #{error.class}"
      end

      def validate_endpoint!(url, environment)
        uri = URI.parse(url.to_s)
        expected_host = environment_config(environment).fetch(:host)
        unless uri.is_a?(URI::HTTPS) && uri.host == expected_host && [nil, 443].include?(uri.port) &&
               uri.userinfo.nil? && uri.fragment.nil?
          raise InvalidToken, "BankID endpoint outside trusted HTTPS origin"
        end
        uri
      end

      def signing_keys(environment, config, refresh: false)
        key = "jwks:#{environment}"
        @cache_mutex.synchronize { @cache.delete(key) } if refresh
        cache_fetch(key) { fetch_json(config.fetch("jwks_uri"), environment) }
      end

      def find_signing_key(key_set, header, environment)
        row = matching_key(key_set, header)
        row ||= matching_key(signing_keys(environment, configuration(environment), refresh: true), header)
        raise InvalidToken, "BankID signing key not found" unless row
        verify_certificate_chain!(row, environment)
      end

      def matching_key(key_set, header)
        Array(key_set.fetch("keys")).find do |candidate|
          candidate["kid"] == header["kid"] && candidate["use"] == "sig" &&
            candidate["alg"] == "ES256" && candidate["kty"] == "EC" && candidate["crv"] == "P-256"
        end
      end

      def verify_certificate_chain!(jwk, environment)
        encoded = Array(jwk["x5c"])
        raise InvalidToken, "BankID signing certificate chain missing" if encoded.length < 2
        certs = encoded.map { |value| OpenSSL::X509::Certificate.new(Base64.strict_decode64(value)) }
        leaf, root = certs.first, certs.last
        expected = trusted_root_fingerprint(environment)
        actual = Digest::SHA256.hexdigest(root.to_der)
        raise InvalidToken, "BankID root fingerprint mismatch" unless secure_equal?(actual, expected)
        store = OpenSSL::X509::Store.new
        store.add_cert(root)
        store.time = Time.now
        raise InvalidToken, "BankID certificate chain invalid" unless store.verify(leaf, certs[1...-1] || [])
        key = JWT::JWK.new(jwk).verify_key
        raise InvalidToken, "BankID JWK differs from leaf certificate" unless leaf.public_key.to_der == key.to_der
        key
      rescue OpenSSL::OpenSSLError, ArgumentError => error
        raise InvalidToken, "BankID signing certificate invalid: #{error.class}"
      end

      def validate_claims!(payload, config, client_id, nonce, now)
        raise InvalidToken, "BankID issuer mismatch" unless payload["iss"] == config["issuer"]
        audience = Array(payload["aud"])
        raise InvalidToken, "BankID audience mismatch" unless audience.include?(client_id.to_s)
        raise InvalidToken, "BankID authorized party mismatch" if audience.length > 1 && payload["azp"] != client_id.to_s
        raise InvalidToken, "BankID subject missing" if payload["sub"].to_s.empty?
        raise InvalidToken, "BankID token expired" unless payload["exp"].is_a?(Numeric) && payload["exp"] > now
        raise InvalidToken, "BankID issued-at invalid" unless payload["iat"].is_a?(Numeric) && payload["iat"] <= now + CLOCK_SKEW
        raise InvalidToken, "BankID token not yet valid" if payload["nbf"].is_a?(Numeric) && payload["nbf"] > now + CLOCK_SKEW
        raise InvalidToken, "BankID nonce mismatch" unless secure_equal?(payload["nonce"], nonce)
        raise InvalidToken, "BankID assurance level is not high" unless HIGH_ASSURANCE_ACR.include?(payload["acr"].to_s)
      end

      def secure_equal?(left, right)
        left.is_a?(String) && right.is_a?(String) && left.bytesize == right.bytesize && Rack::Utils.secure_compare(left, right)
      end
    end
  end
end
