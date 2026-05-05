# frozen_string_literal: true
require "net/http"
require "uri"

module Master
  module Tools
    # Fetches a URL, returns first ~16KB of content with HTML stripped to plain text.
    # Pairs with web_search for two-step research. Governor-permitted.
    class WebFetch
      TIER         = :guarded
      NAME         = "web_fetch".freeze
      DESCRIPTION  = "Fetch a URL and return plain text (HTML stripped).".freeze
      TIMEOUT      = 15
      MAX_BYTES    = 16_000
      HTTP_OK      = "200".freeze
      TAG_RE       = /<[^>]+>/.freeze
      WS_RE        = /[ \t]+/.freeze
      BLANK_RE     = /\n{3,}/.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus      = event_bus
      end

      def call(url:)
        uri = URI(url)
        return Result.err("web_fetch: only http(s)", category: :validation) unless %w[http https].include?(uri.scheme)

        perm = @governor.permit?(NAME, TIER, url)
        return perm if perm.err?

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: TIMEOUT, open_timeout: TIMEOUT) do |h|
          h.get(uri.request_uri, "User-Agent" => "MASTER/1 (web_fetch)")
        end

        return Result.err("web_fetch: HTTP #{response.code}", category: :infrastructure) unless response.code == HTTP_OK

        body = response.body.to_s.byteslice(0, MAX_BYTES * 4)  # over-read, then trim after stripping
        stripped = body.gsub(TAG_RE, " ").gsub(WS_RE, " ").gsub(BLANK_RE, "\n\n").strip[0, MAX_BYTES]
        @bus&.publish("tool:after", tool: NAME, url:)
        Result.ok(stripped)
      rescue StandardError => e
        Result.err("web_fetch: #{e.message}", category: :infrastructure)
      end
    end
  end
end
