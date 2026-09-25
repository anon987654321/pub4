# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Marketplace
  module Payments
    class DinteroClient
      LIVE_API_HOST = "https://api.dintero.com"
      LIVE_CHECKOUT_HOST = "https://checkout.dintero.com"
      TEST_API_HOST = "https://test.dintero.com"
      TEST_CHECKOUT_HOST = "https://test.dintero.com"
      TOKEN_TTL_SKEW = 60

      class Error < StandardError
        attr_reader :status, :body

        def initialize(message, status: nil, body: nil)
          @status = status
          @body = body
          super(message)
        end
      end

      class << self
        def get(path, checkout: false, idempotency_key: nil)
          req = Net::HTTP::Get.new(uri(path, checkout: checkout))
          req["Idempotency-Key"] = idempotency_key if idempotency_key.present?
          request(req)
        end

        def post(path, payload = nil, checkout: false, idempotency_key: nil)
          req = Net::HTTP::Post.new(uri(path, checkout: checkout))
          req["Idempotency-Key"] = idempotency_key if idempotency_key.present?
          req.body = JSON.generate(payload) if payload
          request(req)
        end

        def put(path, payload = nil, checkout: false, idempotency_key: nil)
          req = Net::HTTP::Put.new(uri(path, checkout: checkout))
          req["Idempotency-Key"] = idempotency_key if idempotency_key.present?
          req.body = JSON.generate(payload) if payload
          request(req)
        end

        def configured?
          checkout_configured?
        end

        def checkout_configured?
          required?(
            "DINTERO_ACCOUNT_ID",
            "DINTERO_CLIENT_ID",
            "DINTERO_CLIENT_SECRET",
            "DINTERO_PROFILE_ID",
            "DINTERO_CALLBACK_SECRET"
          )
        end

        def hooks_configured?
          required?(
            "DINTERO_ACCOUNT_ID",
            "DINTERO_CLIENT_ID",
            "DINTERO_CLIENT_SECRET",
            "DINTERO_HOOK_SECRET"
          )
        end

        def token
          return @token if @token && @token[:expires_at] > Time.current.to_i + TOKEN_TTL_SKEW

          @token_mutex ||= Mutex.new
          @token_mutex.synchronize do
            return @token if @token && @token[:expires_at] > Time.current.to_i + TOKEN_TTL_SKEW

            response = authenticate
            expires_in = response["expires_in"].to_i
            expires_in = 300 if expires_in <= 0
            @token = {
              value: response.fetch("access_token"),
              expires_at: Time.current.to_i + expires_in
            }
          end
          @token[:value]
        end

        def reset_token!
          @token_mutex ||= Mutex.new
          @token_mutex.synchronize { @token = nil }
        end

        def api_host
          configured_host(
            ENV["DINTERO_API_BASE"],
            live: LIVE_API_HOST,
            test: TEST_API_HOST
          )
        end

        def checkout_host
          configured_host(
            ENV["DINTERO_CHECKOUT_BASE"],
            live: LIVE_CHECKOUT_HOST,
            test: TEST_CHECKOUT_HOST
          )
        end

        def test_mode?
          ENV["DINTERO_TEST_MODE"].to_s.strip == "1"
        end

        def production?
          defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        end

        def account_id = ENV.fetch("DINTERO_ACCOUNT_ID").strip
        def profile_id = ENV.fetch("DINTERO_PROFILE_ID").strip

        private

        def required?(*names)
          names.all? { |name| ENV[name].to_s.strip.present? }
        end

        def configured_host(value, live:, test:)
          configured = value.to_s.strip
          return (production? && !test_mode?) ? live : test if configured.empty?

          uri = URI(configured)
          raise ArgumentError, "Dintero host must use HTTPS" unless uri.is_a?(URI::HTTPS)

          allowed = [ URI(live).host, URI(test).host ]
          raise ArgumentError, "Dintero host is not approved" unless allowed.include?(uri.host)

          if production? && !test_mode? && uri.host == URI(test).host
            raise ArgumentError, "Dintero test host is disabled in production"
          end

          configured
        rescue URI::InvalidURIError
          raise ArgumentError, "Dintero host is invalid"
        end


        def authenticate
          account = account_id
          uri = URI("#{api_host}/v1/accounts/#{account}/auth/token")
          req = Net::HTTP::Post.new(uri)
          req.basic_auth(ENV.fetch("DINTERO_CLIENT_ID"), ENV.fetch("DINTERO_CLIENT_SECRET"))
          req["Content-Type"] = "application/json"
          req["Accept"] = "application/json"
          req.body = JSON.generate(
            grant_type: "client_credentials",
            audience: "#{api_host}/v1/accounts/#{account}"
          )

          response = request_raw(req)
          parse_response(response, uri)
        end

        def request(req)
          req["Authorization"] = "Bearer #{token}"
          req["Content-Type"] = "application/json"
          req["Accept"] = "application/json"
          response = request_raw(req)
          parse_response(response, req.uri)
        rescue Error => error
          raise unless error.status == 401

          reset_token!
          req["Authorization"] = "Bearer #{token}"
          response = request_raw(req)
          parse_response(response, req.uri)
        end

        def request_raw(req)
          Net::HTTP.start(
            req.uri.host,
            req.uri.port,
            use_ssl: req.uri.scheme == "https",
            open_timeout: 8,
            read_timeout: 20
          ) do |http|
            http.request(req)
          end
        end

        def parse_response(response, uri)
          body = response.body.to_s
          data = body.empty? ? {} : JSON.parse(body)
          return data if response.is_a?(Net::HTTPSuccess)

          message = data.dig("error", "message") || data["message"] || response.code
          raise Error.new(
            "Dintero #{uri.path} failed: #{message}",
            status: response.code.to_i,
            body: body
          )
        rescue JSON::ParserError
          raise Error.new(
            "Dintero #{uri.path} returned invalid JSON",
            status: response.code.to_i,
            body: body
          )
        end

        def uri(path, checkout:)
          base = checkout ? checkout_host : api_host
          URI("#{base}#{path}")
        end
      end
    end
  end
end
