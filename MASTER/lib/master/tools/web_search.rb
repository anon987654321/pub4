# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module Master
  module Tools
    class WebSearch
      QUERY_CHAR_LIMIT = 300
      MAX_QUERY_CHARS  = QUERY_CHAR_LIMIT
      MAX_SEARCH_RESULTS = 5

      NAME          = "web_search"
      DESCRIPTION   = "Search DuckDuckGo instant answers API."
      ENDPOINT      = "https://api.duckduckgo.com/"
      TIMEOUT       = 10

      def initialize(governor:, event_bus: nil)
        @governor = governor        @bus      = event_bus
      end

      def call(query:)
        if query.length > MAX_QUERY_CHARS
          $stderr.puts "web_search: query truncated from #{query.length} to #{MAX_QUERY_CHARS} chars"
          query = query[0, MAX_QUERY_CHARS]
        end

        perm = @governor.permit?(NAME, TIER, query)
        return perm if perm.err?

        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(q: query, format: "json", no_redirect: 1)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: TIMEOUT) { |h|
          h.get(uri.request_uri)
        }

        return Result.err("web_search: HTTP #{response.code}", category: :infrastructure) unless response.code == "200"

        data    = JSON.parse(response.body)
        results = extract_results(data)
        @bus&.publish("tool:after", tool: NAME, query:)
        Result.ok(results)
      rescue => e
        Result.err("web_search: #{e.message}", category: :infrastructure)
      end

      private

      def extract_results(data)
        parts = []
        parts << data["Abstract"] unless data["Abstract"].to_s.empty?
        (data["RelatedTopics"] || []).first(MAX_SEARCH_RESULTS).each { |t| parts << t["Text"] if t["Text"] }
        parts.empty? ? "(no results)" : parts.join("\n\n")
      end
    end
  end
end