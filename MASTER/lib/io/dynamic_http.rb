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
        defn = Io::DynamicTools.lookup(name)
        return Result.err("dynamic_http: unknown tool #{name}", category: :validation) unless defn
        if DynamicTools.elevated?(defn) && !Fiber[:master_elevated]
          return Result.err("dynamic_http: #{name} waits for an elevated session", category: :policy)
        end

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
        # The socket timeouts bound each connect, write and read; only the outer
        # deadline bounds a server that drips one byte inside every read_timeout.
        # A blocked socket read is interruptible, and Net::HTTP.start's block
        # closes the connection as the Timeout::Error unwinds through it.
        Timeout.timeout(TIMEOUT * 2) do
          address = SsrfGuard.pinned_address(uri) or raise SocketError, "#{uri.host} no longer resolves to a public address"
          pinned = SsrfGuard.http_for(uri, address)

          pinned.open_timeout = TIMEOUT
          pinned.read_timeout = TIMEOUT
          pinned.write_timeout = TIMEOUT

          pinned.start do |http|
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

      # Params come from the model, so each value is escaped for the slot it
      # fills: a raw `&admin=1` in a query or a `"` in a JSON body would rewrite
      # the request around it.
      def interpolate(template, params, escape: :url)
        sym = params.transform_keys(&:to_sym)
        template.gsub(/\{(\w+)\}/) do
          value = sym[Regexp.last_match(1).to_sym].to_s
          case escape
          when :url then URI.encode_uri_component(value)
          when :json then JSON.generate(value)[1..-2]
          else URI.encode_www_form_component(value)
          end
        end
      end

      def build_body(defn, params)
        return JSON.generate(params) unless defn["body_template"]

        json = defn.fetch("content_type", "application/json").to_s.include?("json")
        interpolate(defn["body_template"].to_s, params, escape: json ? :json : :form)
      end
    end
  end
end
