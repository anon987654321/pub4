# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "pub4/deploy_paths"

module Shared
  # HTTP client for MASTER's authenticated bridge (TurnRouter / IngressRunner).
  # Prefer this over shelling into bin/cli from Solid Queue workers.
  class MasterClient
    DEFAULT_TIMEOUT = 45

    def self.configured?
      token.present?
    end

    def self.token
      ENV["MASTER_BRIDGE_TOKEN"].to_s.strip.presence ||
        ENV["MASTER_INTERNAL_TOKEN"].to_s.strip.presence
    end

    def self.base_url
      Pub4::DeployPaths.master_bridge_base.to_s.sub(%r{/\z}, "")
    end

    def initialize(base_url: self.class.base_url, token: self.class.token, timeout: DEFAULT_TIMEOUT)
      @base_url = base_url
      @token = token.to_s
      @timeout = timeout
    end

    def available?
      @token.present? && health.fetch("ok", false)
    rescue StandardError
      false
    end

    def health
      get("/bridge/health")
    end

    # Constitutional agent turn. Returns { ok:, output:, error: }.
    def turn(message, session_key: nil, channel: "rails")
      return { ok: false, error: "MASTER_BRIDGE_TOKEN not configured", output: "" } if @token.empty?

      body = {
        message: message.to_s,
        session_key: session_key.presence || "rails:#{Process.pid}",
        channel: channel.to_s,
      }
      post("/bridge/turn", body)
    rescue StandardError => e
      { ok: false, error: e.message, output: "" }
    end

    # Convenience: free-text assist with a domain prefix for logging/routing.
    def assist(prompt, domain: "general", session_key: nil)
      message = "[rails/#{domain}] #{prompt}"
      turn(message, session_key:, channel: "rails-#{domain}")
    end

    private

    def get(path)
      uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
      req = Net::HTTP::Get.new(uri)
      request(uri, req)
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
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: @timeout,
                            use_ssl: uri.scheme == "https") { |http| http.request(req) }
      parsed = JSON.parse(res.body.to_s)
      parsed = parsed.transform_keys(&:to_s)
      if res.code.to_i >= 400
        return { "ok" => false, "error" => parsed["error"] || "HTTP #{res.code}", "output" => "" }
      end

      parsed
    rescue JSON::ParserError
      { "ok" => res.code.to_i < 400, "output" => res.body.to_s, "error" => nil }
    end
  end
end
