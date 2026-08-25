# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module Master
  module Io
    class WebSearch
      TIER = :guarded
      MAX_QUERY_CHARS = 300
      MAX_SEARCH_RESULTS = 5
      HTTP_OK = "200".freeze

      NAME = "web_search".freeze
      DESCRIPTION = "Search DuckDuckGo instant answers API.".freeze
      ENDPOINT = "https://api.duckduckgo.com/".freeze
      TIMEOUT = 10

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(query:)
        query = truncate_query(query)

        perm = @governor.permit?(NAME, TIER, query)
        return perm if perm.err?

        response = fetch_search_response(query)
        return Result.err("web_search: HTTP #{response.code}", category: :infrastructure) unless response.code == HTTP_OK

        data = JSON.parse(response.body)
        results = extract_results(data)
        @bus&.publish("tool:after", tool: NAME, query:)
        Result.ok(results)
      rescue StandardError => e
        Result.err("web_search: #{e.message}", category: :infrastructure)
      end

      def truncate_query(query)
        return query unless query.length > MAX_QUERY_CHARS

        @bus&.publish("tool:warning", tool: NAME, message: "query truncated to #{MAX_QUERY_CHARS} chars")
        query[0, MAX_QUERY_CHARS]
      end

      def fetch_search_response(query)
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(q: query, format: "json", no_redirect: 1)

        Timeout.timeout(TIMEOUT * 2) do
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: TIMEOUT) do |h|
            h.get(uri.request_uri)
          end
        end
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
