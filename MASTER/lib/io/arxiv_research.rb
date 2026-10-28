# frozen_string_literal: true

require "cgi"
require "net/http"
require "rexml/document"
require "rexml/xpath"
require "uri"

module Master
  module Io
    # Search arXiv metadata and link to the HTML rendering hosted by ar5iv.
    # Abstracts and HTML are untrusted research material, never instructions.
    class ArxivResearch
      TIER = :guarded
      NAME = "arxiv_research".freeze
      DESCRIPTION = "Search public arXiv papers, return abstracts and ar5iv HTML links, and optionally read a bounded full-text excerpt.".freeze
      ENDPOINT = "https://export.arxiv.org/api/query".freeze
      AR5IV_HOST = "ar5iv.labs.arxiv.org".freeze
      ATOM_NS = "http://www.w3.org/2005/Atom".freeze
      TIMEOUT = 15
      MAX_QUERY_CHARS = 300
      MAX_RESPONSE_BYTES = 2 * 1024 * 1024
      MAX_RESULTS = 10
      MAX_ABSTRACT_CHARS = 1_200
      MAX_FULL_TEXT_CHARS = 12_000
      ALLOWED_SORTS = %w[relevance submittedDate lastUpdatedDate].freeze
      ID_RE = /\A(?:\d{4}\.\d{4,5}(?:v\d+)?|[A-Za-z.-]+\/\d{7}(?:v\d+)?)\z/.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(query:, sort_by: "relevance", limit: 5, full_text: false)
        display_query = query.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip[0, MAX_QUERY_CHARS].to_s
        search_terms = normalize_query(display_query)
        return Result.err("arxiv_research: provide a paper topic or research question", category: :validation) if search_terms.empty?

        sort_by = ALLOWED_SORTS.include?(sort_by.to_s) ? sort_by.to_s : "relevance"
        limit = [[limit.to_i, 1].max, MAX_RESULTS].min
        perm = @governor.permit?(NAME, TIER, search_terms)
        return perm if perm.err?

        response = search_response(query: search_terms, sort_by:, limit:)
        return Result.err("arxiv_research: HTTP #{response.code}", category: :infrastructure) unless response.code.to_s == "200"

        body = response.body.to_s
        return Result.err("arxiv_research: response exceeds #{MAX_RESPONSE_BYTES} bytes", category: :validation) if body.bytesize > MAX_RESPONSE_BYTES

        papers = parse_papers(body).first(limit)
        value = if papers.empty?
                  "No arXiv papers found for #{search_terms.inspect}."
                else
                  papers.each_with_index.map { |paper, index| format_paper(paper, index + 1) }.join("\n\n")
                end

        if full_text && !papers.empty?
          paper = papers.first
          begin
            excerpt = fetch_full_text(paper[:id])
            value = "#{value}\n\nFull-text excerpt from ar5iv (first result only):\n#{excerpt}"
          rescue StandardError => e
            @bus&.publish("tool:warning", tool: NAME, message: "ar5iv full text unavailable: #{e.message}")
            value = "#{value}\n\nFull-text retrieval: FAILED (#{e.message})"
          end
        end

        screened = injection_guard.screen(value, tool: NAME, source: "export.arxiv.org", bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: "export.arxiv.org")
        @bus&.publish("tool:after", tool: NAME, query: search_terms, count: papers.length, full_text: full_text == true)
        Result.ok(screened)
      rescue REXML::ParseException => e
        Result.err("arxiv_research: invalid Atom response (#{e.message})", category: :infrastructure)
      rescue StandardError => e
        Result.err("arxiv_research: #{e.message}", category: :infrastructure)
      end

      private

      def normalize_query(value)
        query = value.to_s
          .gsub(/\b(?:please|find|search|show|summarize|summarise|review|read|arxiv|ar5iv|academic|research|literature|papers?|about|on|for|the)\b/i, " ")
          .gsub(/\s+/, " ").strip
        terms = query.scan(/[\p{L}\p{N}][\p{L}\p{N}._+-]*/u).first(12)
        terms.join(" ")
      end

      def search_response(query:, sort_by:, limit:)
        terms = query.split(/\s+/).map { |term| "all:#{term}" }.join(" AND ")
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(
          search_query: terms,
          start: 0,
          max_results: limit,
          sortBy: sort_by,
          sortOrder: "descending",
        )
        get_response(uri)
      end

      def get_response(uri)
        raise "refused unexpected research host" unless uri.is_a?(URI::HTTPS) &&
          %w[export.arxiv.org ar5iv.labs.arxiv.org].include?(uri.host.to_s.downcase)

        address = SsrfGuard.pinned_address(uri)
        raise "refused internal/reserved address" unless address

        client = SsrfGuard.http_for(uri, address, timeout: TIMEOUT)
        client.start do |http|
          http.get(uri.request_uri, {
            "User-Agent" => "MASTER/1 (arxiv_research)",
            "Accept" => "application/atom+xml,text/html;q=0.9",
          })
        end
      end

      def parse_papers(body)
        document = REXML::Document.new(body)
        namespace = { "atom" => ATOM_NS }
        REXML::XPath.match(document, "//atom:entry", namespace).filter_map do |entry|
          id_url = xpath_text(entry, "atom:id", namespace)
          id = arxiv_id(id_url)
          next unless id

          authors = REXML::XPath.match(entry, "atom:author/atom:name", namespace)
            .map { |node| node.text.to_s.strip }.reject(&:empty?).first(5)
          {
            id:,
            title: xpath_text(entry, "atom:title", namespace).gsub(/\s+/, " ").strip,
            summary: xpath_text(entry, "atom:summary", namespace).gsub(/\s+/, " ").strip[0, MAX_ABSTRACT_CHARS],
            published: xpath_text(entry, "atom:published", namespace),
            authors:,
          }
        end
      end

      def xpath_text(node, path, namespace)
        REXML::XPath.first(node, path, namespace)&.text.to_s
      end

      def arxiv_id(value)
        uri = URI.parse(value.to_s)
        return unless %w[arxiv.org export.arxiv.org].include?(uri.host.to_s.downcase)
        match = %r{\A/abs/(.+)\z}.match(uri.path.to_s)
        id = match && match[1]
        id if id && ID_RE.match?(id)
      rescue URI::InvalidURIError
        nil
      end

      def format_paper(paper, index)
        authors = paper[:authors].empty? ? "Authors not listed" : paper[:authors].join(", ")
        base = "https://arxiv.org/abs/#{paper[:id]}"
        html = "https://#{AR5IV_HOST}/html/#{paper[:id]}"
        lines = [
          "#{index}. #{paper[:title]}",
          "arXiv: #{base}",
          "HTML: #{html}",
          "Published: #{paper[:published]}",
          "Authors: #{authors}",
        ]
        lines << "Abstract: #{paper[:summary]}" unless paper[:summary].empty?
        lines.join("\n")
      end

      def fetch_full_text(id)
        raise "invalid arXiv identifier" unless ID_RE.match?(id.to_s)

        uri = URI("https://#{AR5IV_HOST}/html/#{id}")
        response = get_response(uri)
        raise "HTTP #{response.code}" unless response.code.to_s == "200"

        body = response.body.to_s
        raise "response exceeds #{MAX_RESPONSE_BYTES} bytes" if body.bytesize > MAX_RESPONSE_BYTES

        text = body.gsub(/<(script|style)\b[^>]*>.*?<\/\1\s*>/im, " ")
          .gsub(/<[^>]*>/m, " ")
          .then { |value| CGI.unescapeHTML(value) }
          .gsub(/\s+/, " ").strip
        raise "empty HTML text" if text.empty?

        text[0, MAX_FULL_TEXT_CHARS]
      end

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
