# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Io
    class Gist
      TIER = :guarded
      NAME = "gist".freeze
      DESCRIPTION = "Read a public GitHub Gist as untrusted source text; never execute it.".freeze
      TIMEOUT = 15
      MAX_BYTES = 2 * 1024 * 1024
      GIST_RE = %r{\Ahttps://gist\.github\.com/([^/]+)/([0-9a-fA-F]+)/?(?:#.*)?\z}.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(url:, full: false)
        match = GIST_RE.match(url.to_s)
        return Result.err("gist: expected https://gist.github.com/<user>/<id>", category: :validation) unless match

        user, id = match.captures
        perm = @governor.permit?(NAME, TIER, url.to_s)
        return perm if perm.err?

        uri = URI("https://gist.githubusercontent.com/#{user}/#{id}/raw")
        address = SsrfGuard.pinned_address(uri)
        return Result.err("gist: refused internal/reserved address", category: :validation) unless address

        response = http(uri, address)
        return Result.err("gist: HTTP #{response.code}", category: :infrastructure) unless response.code == "200"

        body = response.body.to_s
        limit = full ? MAX_BYTES : 16_000
        return Result.err("gist: response exceeds #{limit} bytes; use full=true or fetch a narrower gist", category: :validation) if body.bytesize > limit

        value = injection_guard.screen(body, tool: NAME, source: uri.to_s, bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: uri.to_s)
        @bus&.publish("tool:after", tool: NAME, url: url.to_s)
        Result.ok(value)
      rescue StandardError => e
        Result.err("gist: #{e.message}", category: :infrastructure)
      end

      private

      def http(uri, address)
        client = SsrfGuard.http_for(uri, address)
        client.read_timeout = TIMEOUT
        client.open_timeout = TIMEOUT
        client.start { |h| h.get(uri.request_uri, "User-Agent" => "MASTER/1 (gist)") }
      end

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
