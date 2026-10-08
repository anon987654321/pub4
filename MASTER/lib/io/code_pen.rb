# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Io
    class CodePen
      TIER = :guarded
      NAME = "codepen".freeze
      DESCRIPTION = "Browse CodePen trending ideas or inspect a public Pen without executing third-party code.".freeze
      TIMEOUT = 15
      MAX_BYTES = 2 * 1024 * 1024
      MAX_RESULTS = 12
      TRENDING_URL = "https://codepen.io/trending".freeze
      PEN_RE = %r{\Ahttps://codepen\.io/([^/]+)/pen/([^/?#]+)/?\z}.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(mode: "trending", url: nil, limit: 8)
        perm = @governor.permit?(NAME, TIER, mode.to_s)
        return perm if perm.err?

        case mode.to_s
        when "trending"
          trending(limit:)
        when "inspect"
          inspect_pen(url:)
        else
          Result.err("codepen: unknown mode #{mode}", category: :validation)
        end
      rescue StandardError => e
        Result.err("codepen: #{e.message}", category: :infrastructure)
      end

      private

      def trending(limit:)
        limit = [[limit.to_i, 1].max, MAX_RESULTS].min
        body = get(TRENDING_URL)
        items = extract_trending(body).first(limit)
        screened = injection_guard.screen(items.to_json, tool: NAME, source: TRENDING_URL, bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: TRENDING_URL)
        @bus&.publish("tool:after", tool: NAME, mode: "trending", count: items.size)
        Result.ok(JSON.parse(screened))
      end

      def inspect_pen(url:)
        match = PEN_RE.match(url.to_s)
        return Result.err("codepen: expected https://codepen.io/<user>/pen/<slug>", category: :validation) unless match

        user, slug = match.captures
        base = "https://codepen.io/#{user}/pen/#{slug}"
        payload = %w[html css js].filter_map do |ext|
          response = fetch(rewrite(base, ext))
          next unless response

          { "type" => ext, "source" => response }
        end
        return Result.err("codepen: no readable panels at #{base}", category: :infrastructure) if payload.empty?

        text = injection_guard.screen(payload.to_json, tool: NAME, source: base, bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: base)
        @bus&.publish("tool:after", tool: NAME, mode: "inspect", url: base)
        Result.ok(JSON.parse(text))
      end

      def rewrite(base, ext)
        "#{base}.#{ext}"
      end

      def get(url)
        uri = URI(url)
        address = SsrfGuard.pinned_address(uri)
        raise "refused internal/reserved address" unless address

        response = http(uri, address)
        raise "HTTP #{response.code}" unless response.code == "200"

        response.body.to_s.byteslice(0, MAX_BYTES)
      end

      def fetch(url)
        get(url)
      rescue StandardError => e
        @bus&.publish("tool:warning", tool: NAME, message: "#{url}: #{e.message}")
        nil
      end

      def http(uri, address)
        client = SsrfGuard.http_for(uri, address)
        client.read_timeout = TIMEOUT
        client.open_timeout = TIMEOUT
        client.start { |h| h.get(uri.request_uri, "User-Agent" => "MASTER/1 (codepen)") }
      end

      def extract_trending(body)
        cleaned = body.gsub(/<script.*?<\/script>/mi, " ").gsub(/<style.*?<\/style>/mi, " ")
        pairs = cleaned.scan(%r{href=["']/([^/"]+)/pen/([^?"']+)["'][^>]*>(.*?)</a>}mi)
        pairs.map do |user, slug, label|
          title = label.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
          next if title.empty?

          {
            "title" => title,
            "user" => user,
            "url" => "https://codepen.io/#{user}/pen/#{slug}"
          }
        end.compact.uniq { |item| item["url"] }
      end

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
