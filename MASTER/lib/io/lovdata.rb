# frozen_string_literal: true

require "time"
require "uri"

module Master
  module Io
    # One-document Lovdata lookup. This is intentionally not a crawler, bulk
    # downloader, cache or legal RAG index. Search returns official links only.
    # Reading document text requires an explicit local acknowledgement of the
    # current Lovdata AI-use restrictions.
    class Lovdata
      NAME = "lovdata".freeze
      TIER = :guarded
      DESCRIPTION = "Find individual Norwegian laws and regulations on Lovdata. Search returns links; reading one document requires the operator's no-storage/no-training acknowledgement. No crawling, bulk download or legal corpus.".freeze
      AI_USE_ENV = "MASTER_LOVDATA_AI_USE".freeze
      AI_USE_ACK = "single-document-no-storage-no-training".freeze
      MAX_REFERENCE_CHARS = 190
      MAX_SECTION_CHARS = 24
      MAX_RESULTS = 5
      DOC_PATH = %r{\A/dokument/NL/(?:lov|forskrift)/\d{4}-\d{2}-\d{2}-\d+(?:/(?:%C2%A7)?[A-Za-z0-9][A-Za-z0-9.-]*)?\z}i.freeze
      LAW_CODE = /\A(LOV|FOR)-(\d{4}-\d{2}-\d{2}-\d+)\z/i.freeze
      SECTION = /\A(?:§\s*)?([0-9]+[a-z]?(?:-[0-9]+[a-z]?)?)\z/i.freeze
      URL_RE = %r{\Ahttps://(?:www\.)?lovdata\.no/}i.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
        @search = WebSearch.new(governor:, event_bus:)
        @fetch = WebFetch.new(governor:, event_bus:)
      end

      def call(reference:, action: "lookup", section: nil)
        value = clean_reference(reference)
        return Result.err("lovdata: provide a law title, LOV-/FOR-code, or official Lovdata document URL", category: :validation) if value.empty?

        mode = action.to_s.downcase
        return Result.err("lovdata: action must be search or lookup", category: :validation) unless %w[search lookup].include?(mode)

        permission = @governor.permit?(NAME, TIER, "#{mode} #{value}")
        return permission if permission.err?

        section_value = normalize_section(section || section_from(value))
        return Result.err("lovdata: invalid section reference", category: :validation) if section && section_value.nil?

        candidates = direct_candidate(value, section_value)
        if value.match?(%r{\Ahttps?://}i) && candidates.empty?
          return Result.err("lovdata: URL must be an official single-document Lovdata URL", category: :validation)
        end
        candidates = search_candidates(value, section_value) if candidates.empty?
        return candidates if candidates.is_a?(Result)
        return Result.err("lovdata: no official public law or regulation matched #{value.inspect}", category: :provider_error) if candidates.empty?

        return Result.ok(format_candidates(candidates)) if mode == "search"

        if candidates.length != 1
          return Result.ok("lovdata: more than one official document matched. Choose the exact source URL or LOV-/FOR-code, then request that single document.\n\n#{format_candidates(candidates)}")
        end

        url = candidates.first.fetch(:url)
        unless ai_use_acknowledged?
          return Result.err(
            "lovdata: document text retrieval is disabled. Lovdata's current terms restrict AI use to eligible individual public documents and require no storage or model training. After verifying that your chosen runtime meets those conditions, set #{AI_USE_ENV}=#{AI_USE_ACK}. Search results and official links remain available.",
            category: :policy,
          )
        end

        fetched = @fetch.call(url:, full: false)
        return fetched if fetched.err?

        body = fetched.value!.to_s
        return Result.err("lovdata: official page returned no readable text", category: :provider_error) if body.strip.empty?

        output = [
          "Source: #{url}",
          "Retrieved: #{Time.now.utc.iso8601}",
          "Scope: one individual public law/regulation; no local content cache is written.",
          "Important: verify the current version and effective date on the official Lovdata page. This is source retrieval, not legal advice.",
          "",
          body[0, 12_000],
        ].join("\n")
        @bus&.publish("tool:after", tool: NAME, action: "lookup", source: url, bytes: body.bytesize)
        Result.ok(output)
      rescue StandardError => e
        Result.err("lovdata: #{e.class}: #{e.message.lines.first.to_s.strip[0, 180]}", category: :infrastructure)
      end

      private

      def clean_reference(value)
        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip[0, MAX_REFERENCE_CHARS].to_s
      end

      def normalize_section(value)
        return if value.to_s.strip.empty?

        match = SECTION.match(value.to_s.strip)
        match && match[1]
      end

      def section_from(value)
        value.to_s[/§\s*([0-9]+[a-z]?(?:-[0-9]+[a-z]?)?)/i, 1]
      end

      def direct_candidate(reference, section)
        raw = reference.to_s
        if raw.match?(URL_RE)
          uri = URI.parse(raw)
          return [] unless valid_document_uri?(uri)

          return [{ title: "Lovdata document", url: with_section(uri, section).to_s }]
        end

        if (match = LAW_CODE.match(raw.upcase))
          kind = match[1] == "LOV" ? "lov" : "forskrift"
          uri = URI("https://lovdata.no/dokument/NL/#{kind}/#{match[2]}")
          return [{ title: raw.upcase, url: with_section(uri, section).to_s }]
        end

        []
      rescue URI::InvalidURIError
        []
      end

      def search_candidates(reference, section)
        search_result = @search.call(query: search_query(reference, section))
        return search_result if search_result.err?

        rows = parse_search_results(search_result.value!.to_s)
        rows = rows.map { |row| row.merge(url: with_section(URI(row[:url]), section).to_s) }
        rows.first(MAX_RESULTS)
      end

      def search_query(reference, section)
        suffix = section ? " § #{section}" : ""
        "site:lovdata.no/dokument/NL/lov OR site:lovdata.no/dokument/NL/forskrift #{reference}#{suffix}"
      end

      def parse_search_results(text)
        text.to_s.split(/\n{2,}/).filter_map do |block|
          lines = block.lines.map(&:strip).reject(&:empty?)
          url = lines.find { |line| line.start_with?("https://") }
          next unless url

          uri = URI.parse(url)
          next unless valid_document_uri?(uri)

          title = lines.first.to_s.sub(/\A\d+\.\s*/, "")
          snippet = lines[(lines.index(url) || 0) + 1].to_s
          { title: title.empty? ? "Lovdata document" : title, url: uri.to_s, snippet: snippet[0, 300] }
        rescue URI::InvalidURIError
          nil
        end.uniq { |row| row[:url] }
      end

      def valid_document_uri?(uri)
        host = uri.host.to_s.downcase.sub(/\Awww\./, "")
        uri.scheme == "https" && uri.port == 443 && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
          host == "lovdata.no" && uri.path.match?(DOC_PATH)
      end

      def with_section(uri, section)
        return uri if section.nil? || uri.path.split("/").length >= 6

        copy = uri.dup
        copy.path = "#{copy.path}/#{URI::DEFAULT_PARSER.escape("§#{section}", /[^A-Za-z0-9\-._~]/)}"
        copy
      end

      def format_candidates(rows)
        rows.each_with_index.map do |row, index|
          [ "#{index + 1}. #{row[:title]}", row[:url], row[:snippet].to_s ].reject(&:empty?).join("\n")
        end.join("\n\n")
      end

      def ai_use_acknowledged?
        ENV[AI_USE_ENV].to_s == AI_USE_ACK
      end
    end
  end
end
