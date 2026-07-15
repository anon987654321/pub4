# frozen_string_literal: true

require "json"

module Master
  module Reach
    # Maps OpenClaw gateway sessions onto MASTER trust tiers and gateway metadata.
    module OpenclawBridge
      TRUST_LEVELS = %i[owner untrusted].freeze

      module_function

      def parse_body(raw)
        data = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
        deep_symbolize(data)
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "OpenclawBridge.parse_body")
        {}
      end

      def deep_symbolize(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), out|
            out[key.to_sym] = deep_symbolize(value)
          end
        when Array
          obj.map { |item| deep_symbolize(item) }
        else
          obj
        end
      end

      def session_key(body)
        (body[:session_key] || body[:session_id]).to_s.strip
      end

      def channel(body)
        body.fetch(:channel, "api").to_s.strip.downcase
      end

      def trust(body)
        raw = body.dig(:metadata, :trust) || body[:trust]
        sym = raw.to_s.strip.downcase.to_sym
        TRUST_LEVELS.include?(sym) ? sym : :untrusted
      end

      def elevated?(body)
        trust(body) == :owner
      end

      def gateway_metadata(body)
        meta = body[:metadata].is_a?(Hash) ? body[:metadata] : {}
        {
          openclaw_session: session_key(body),
          openclaw_channel: channel(body),
          openclaw_turn_id: meta[:openclaw_turn_id] || meta["openclaw_turn_id"],
          sender: meta[:sender] || meta["sender"],
          trust: trust(body),
        }.compact
      end
    end
  end
end