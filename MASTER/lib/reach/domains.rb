# frozen_string_literal: true

require "net/http"
require "json"

module Master
  module Reach
    # CE02: domeneshop API for DNS record management.
    class Domains
      NAME = "domains".freeze
      API_BASE = "https://api.domeneshop.no/v0".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def list_records(domain)
        uri = URI("#{API_BASE}/domains/#{domain}/dns")
        response = authorized_get(uri)
        Result.ok(JSON.parse(response.body))
      rescue StandardError => e
        Result.err("domains: #{e.message}")
      end

      private

      def authorized_get(uri)
        token = ENV.fetch("DOMENESHOP_TOKEN", "")
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          req = Net::HTTP::Get.new(uri)
          req["Authorization"] = "Bearer #{token}" unless token.empty?
          http.request(req)
        end
      end
    end
  end
end