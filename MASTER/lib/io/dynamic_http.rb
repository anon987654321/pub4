# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Io
    class DynamicHttp
      TIER = :guarded
      NAME = "dynamic_http".freeze
      DESCRIPTION = "Call a configured HTTP endpoint from data/tools.dynamic.yml.".freeze
      TIMEOUT = 20
      MAX_BYTES = 32_000

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(name:, params: {})
        defn = Ground::DynamicTools.lookup(name)
        return Result.err("dynamic_http: unknown tool #{name}", category: :validation) unless defn

        perm = @governor.permit?(NAME, TIER, "#{name} #{params}")
        return perm if perm.err?

        uri = resolve_and_validate_uri(defn, params)
        return uri if uri.is_a?(Result::Err)

        method = defn.fetch("method", "GET").to_s.upcase
        response = perform_request(uri, method, defn, params)

        text = response.body.to_s.byteslice(0, MAX_BYTES)
        @bus&.publish("tool:after", tool: NAME, dynamic: name, status: response.code.to_i)
        Result.ok("HTTP #{response.code}\n#{text}")
      rescue StandardError => e
        Result.err("dynamic_http: #{e.message}", category: :infrastructure)
      end

      def resolve_and_validate_uri(defn, params)
        url = interpolate(defn.fetch("url").to_s, params)
        uri = URI(url)
        return Result.err("dynamic_http: only http(s)", category: :validation) unless %w[http https].include?(uri.scheme)
        return Result.err("dynamic_http: refused internal/reserved address", category: :validation) unless SsrfGuard.safe_uri?(uri)

        uri
      end

      def perform_request(uri, method, defn, params)
        Timeout.timeout(TIMEOUT * 2) do
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: TIMEOUT) do |http|
            case method
            when "POST", "PUT", "PATCH"
              req = Net::HTTP.const_get(method.capitalize).new(uri)
              body = build_body(defn, params)
              req["Content-Type"] = defn.fetch("content_type", "application/json")
              req.body = body
              http.request(req)
            else
              http.get(uri.request_uri)
            end
          end
        end
      end

      private

      def interpolate(template, params)
        sym = params.transform_keys(&:to_sym)
        template.gsub(/\{(\w+)\}/) { sym[Regexp.last_match(1).to_sym] || sym[Regexp.last_match(1)] || "" }
      end

      def build_body(defn, params)
        return JSON.generate(params) unless defn["body_template"]

        interpolate(defn["body_template"].to_s, params)
      end
    end
  end
end
