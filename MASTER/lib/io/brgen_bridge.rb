# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "../result"

module Master
  module Io
    # Read-only bridge to brgen's local status endpoint (RAILS/brgen's
    # InternalController) — lets the chat agent report live tenant activity
    # without a public API surface. Both processes run on the same VPS;
    # brgen's Falcon port comes from RAILS/apps.yml, not a public domain.
    module BrgenBridge
      module_function

      BRGEN_PORT = 38_182
      TIMEOUT = 5

      def status
        token = ENV["MASTER_INTERNAL_TOKEN"].to_s
        return Result.err("brgen: MASTER_INTERNAL_TOKEN not configured", category: :validation) if token.empty?

        uri = URI("http://127.0.0.1:#{BRGEN_PORT}/internal/status")
        req = Net::HTTP::Get.new(uri)
        req["X-Internal-Token"] = token

        res = Net::HTTP.start(uri.host, uri.port, read_timeout: TIMEOUT, open_timeout: TIMEOUT) { |http| http.request(req) }
        return Result.err("brgen: internal status #{res.code}", category: :infrastructure) unless res.code.to_i == 200

        Result.ok(JSON.parse(res.body))
      rescue JSON::ParserError => e
        Result.err("brgen: bad status response: #{e.message}", category: :infrastructure)
      rescue StandardError => e
        Result.err("brgen: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def summary
        return status.message unless status.ok?

        s = status.value!
        "ok: brgen tenant=#{s['city']} at #{s['generated_at']}\n" \
          "marketplace_listings=#{s['marketplace_listings']} takeaway_open_orders=#{s['takeaway_open_orders']} " \
          "playlist_tracks=#{s['playlist_tracks']} tv_live_streams=#{s['tv_live_streams']} dating_profiles=#{s['dating_profiles']}"
      end
    end
  end
end
