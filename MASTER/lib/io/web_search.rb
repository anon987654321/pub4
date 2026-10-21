# frozen_string_literal: true
require "net/http"
require "uri"
require "json"
require "cgi"
require_relative "../ground/evidence_router"

module Master
  module Io
    class WebSearch
      TIER = :guarded
      MAX_QUERY_CHARS = 300
      MAX_SEARCH_RESULTS = 5
      HTTP_OK = "200".freeze

      NAME = "web_search".freeze
      DESCRIPTION = "Search ordinary ranked web results with titles, source URLs and snippets.".freeze
      ENDPOINT = "https://html.duckduckgo.com/html/".freeze
      TIMEOUT = 10
      MAX_RESPONSE_BYTES = 2 * 1024 * 1024

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(query:)
        # Enforce sensitive-query minimization at the tool boundary, including
        # direct LLM tool calls that bypass the agent's evidence preflight.
        query = Master::Ground::EvidenceRouter.web_search_query(query)
        query = truncate_query(query)

        perm = @governor.permit?(NAME, TIER, query)
        return perm if perm.err?

        response = fetch_search_response(query)
        return Result.err("web_search: HTTP #{response.code}", category: :infrastructure) unless response.code == HTTP_OK

        return Result.err("web_search: response exceeds #{MAX_RESPONSE_BYTES} bytes", category: :validation) if response.body.to_s.bytesize > MAX_RESPONSE_BYTES

        results = extract_results(response.body.to_s)
        results = injection_guard.screen(results, tool: NAME, source: "duckduckgo", bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: "duckduckgo")
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
        uri.query = URI.encode_www_form(q: query)
        address = SsrfGuard.pinned_address(uri)
        raise "refused internal/reserved address" unless address

        http = SsrfGuard.http_for(uri, address, timeout: TIMEOUT)
        http.start do |client|
          client.get(uri.request_uri, {
            "User-Agent" => "MASTER/1 (web_search)",
            "Accept" => "text/html,application/xhtml+xml",
          })
        end
      end

      private

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end

      # Preserve compatibility with recorded instant-answer fixtures while
      # preferring ranked live results with canonical URLs for verification.
      def extract_results(body)
        data = JSON.parse(body)
        if data.is_a?(Hash) && (data.key?("Abstract") || data.key?("RelatedTopics"))
          parts = []
          parts << data["Abstract"] unless data["Abstract"].to_s.empty?
          Array(data["RelatedTopics"]).each do |topic|
            next unless topic.is_a?(Hash)
            parts << topic["Text"] unless topic["Text"].to_s.empty?
            Array(topic["Topics"]).each do |nested|
              parts << nested["Text"] if nested.is_a?(Hash) && !nested["Text"].to_s.empty?
            end
          end
          text = parts.first(MAX_SEARCH_RESULTS + 1).join("\n\n")
          return text.empty? ? "No web results found." : text
        end
        html_results(body)
      rescue JSON::ParserError
        html_results(body)
      end

      def html_results(body)
        return "No web results found." if body.to_s.bytesize > MAX_RESPONSE_BYTES

        anchors = body.to_s.scan(/<a\b([^>]*)>(.*?)<\/a\s*>/im)
        items = anchors.filter_map do |attributes, markup|
          next unless attribute(attributes, "class").to_s.split.include?("result__a")
          title = plain_text(markup)
          url = result_url(attribute(attributes, "href"))
          next if title.empty? || url.nil?
          { title:, url: }
        end.uniq { |item| item[:url] }.first(MAX_SEARCH_RESULTS)

        tags = body.to_s.scan(/<(a|div|span)\b([^>]*)>(.*?)<\/\1\s*>/im)
        snippets = tags.filter_map do |_tag, attributes, markup|
          next unless attribute(attributes, "class").to_s.split.include?("result__snippet")
          text = plain_text(markup)
          text unless text.empty?
        end
        return "No web results found." if items.empty?

        items.each_with_index.map do |item, index|
          lines = ["#{index + 1}. #{item[:title]}", item[:url]]
          lines << snippets[index] unless snippets[index].to_s.empty?
          lines.join("\n")
        end.join("\n\n")
      end

      def attribute(attributes, name)
        attributes.to_s[/\b#{Regexp.escape(name)}\s*=\s*(["'])(.*?)\1/im, 2]
      end

      def plain_text(markup)
        CGI.unescapeHTML(markup.to_s.gsub(/<[^>]*>/m, " ").gsub(/\s+/, " ").strip)
      end

      def result_url(href)
        return if href.to_s.empty?
        uri = URI.join(ENDPOINT, CGI.unescapeHTML(href.to_s))
        if uri.host.to_s.downcase.match?(/(?:\A|\.)duckduckgo\.com\z/)
          target = URI.decode_www_form(uri.query.to_s).to_h["uddg"]
          uri = URI.parse(CGI.unescapeHTML(target)) unless target.to_s.empty?
        end
        return unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        nil
      end
    end
  end
end
