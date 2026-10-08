# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Contracts
  module MasterClient
    DEFAULT_TIMEOUT = 45

    module_function

    def configured?
      !token.empty?
    end

    def token
      value = ENV["MASTER_INGRESS_TOKEN"].to_s.strip
      value unless value.empty?
    end

    def base_url
      value = ENV["MASTER_WEB_URL"].to_s.strip.sub(%r{/\z}, "")
      value.empty? ? "http://127.0.0.1:53187" : value
    end

    class Client
      def initialize(base_url: Contracts::MasterClient.base_url, token: Contracts::MasterClient.token,
                     timeout: Contracts::MasterClient::DEFAULT_TIMEOUT)
        @base_url = base_url
        @token = token.to_s
        @timeout = timeout
      end

      def available?
        @token != "" && health.fetch("ok", false)
      rescue StandardError
        false
      end

      def health
        get("/ingress/health")
      end

      def turn(message, session_key: nil, channel: "rails")
        return { ok: false, error: "MASTER_INGRESS_TOKEN not configured", output: "" } if @token.empty?

        key = session_key.to_s.strip
        key = "rails:#{Process.pid}" if key.empty?
        post("/ingress/webhook/rails_master",
             { message: message.to_s, session_key: key, channel: channel.to_s })
      rescue StandardError => e
        { ok: false, error: e.message, output: "" }
      end

      def assist(prompt, domain: "general", session_key: nil)
        turn("[rails/#{domain}] #{prompt}", session_key:, channel: "rails-#{domain}")
      end

      private

      def get(path)
        uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
        request(uri, Net::HTTP::Get.new(uri))
      end

      def post(path, body)
        uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@token}"
        req.body = JSON.generate(body)
        request(uri, req)
      end

      def request(uri, req)
        res = Net::HTTP.start(uri.host, uri.port,
                              open_timeout: 5, read_timeout: @timeout,
                              use_ssl: uri.scheme == "https") { |http| http.request(req) }
        parsed = JSON.parse(res.body.to_s).transform_keys(&:to_s)
        return { "ok" => false, "error" => parsed["error"] || "HTTP #{res.code}", "output" => "" } if res.code.to_i >= 400
        parsed
      rescue JSON::ParserError
        { "ok" => res.code.to_i < 400, "output" => res.body.to_s, "error" => nil }
      end
    end
  end
end
