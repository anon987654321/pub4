# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Marketplace
  module Payments
    class DinteroClient
      AUTH_HOST = "https://api.dintero.com"
      CHECKOUT_HOST = "https://checkout.dintero.com"
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
        def get(path, checkout: false)
          request(Net::HTTP::Get.new(uri(path, checkout: checkout)))
        end

        def post(path, payload = nil, checkout: false, idempotency_key: nil)
          req = Net::HTTP::Post.new(uri(path, checkout: checkout))
          req["Idempotency-Key"] = idempotency_key if idempotency_key.present?
          request(req, payload)
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

        def configured?
          %w[DINTERO_ACCOUNT_ID DINTERO_CLIENT_ID DINTERO_CLIENT_SECRET DINTERO_PROFILE_ID
             DINTERO_CALLBACK_SECRET DINTERO_HOOK_SECRET].all? do |name|
            ENV[name].to_s.strip.present?
          end
        end

        def account_id = ENV.fetch("DINTERO_ACCOUNT_ID").strip
        def profile_id = ENV.fetch("DINTERO_PROFILE_ID").strip

        private

        def authenticate
          account = account_id
          uri = URI("#{AUTH_HOST}/v1/accounts/#{account}/auth/token")
          req = Net::HTTP::Post.new(uri)
          req.basic_auth(ENV.fetch("DINTERO_CLIENT_ID"), ENV.fetch("DINTERO_CLIENT_SECRET"))
          req["Content-Type"] = "application/json"
          req.body = JSON.generate(
            grant_type: "client_credentials",
            audience: "#{AUTH_HOST}/v1/accounts/#{account}"
          )

          response = request_raw(req)
          parse_response(response, uri)
        end

        def request(req, payload = nil)
          req["Authorization"] = "Bearer #{token}"
          req["Content-Type"] = "application/json"
          req["Accept"] = "application/json"
          response = request_raw(req)
          parse_response(response, req.uri)
        rescue Error => e
          reset_token! if e.status == 401
          raise
        end

        def request_raw(req)
          Net::HTTP.start(
            req.uri.host,
            req.uri.port,
            use_ssl: req.uri.scheme == "https",
            open_timeout: 8,
            read_timeout: 20
          ) do |http|
            req.body ||= nil
            http.request(req)
          end
        end

        def parse_response(response, uri)
          body = response.body.to_s
          data = body.empty? ? {} : JSON.parse(body)
          return data if response.is_a?(Net::HTTPSuccess)

          message = data.dig("error", "message") || data["message"] || response.code
          raise Error, "Dintero #{uri.path} failed: #{message}"
        rescue JSON::ParserError
          raise Error.new("Dintero #{uri.path} returned invalid JSON", status: response.code.to_i, body: body)
        end

        def uri(path, checkout:)
          base = checkout ? CHECKOUT_HOST : AUTH_HOST
          URI("#{base}#{path}")
        end
      end
    end
  end
end
