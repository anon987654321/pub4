# frozen_string_literal: true

require "uri"

module Master
  module Io
    # Reference discovery for linguistics and natural conversation. This tool
    # finds dictionary and language-authority sources; interpretation and
    # conversational coaching remain with the language model.
    class Linguist
      NAME = "linguist".freeze
      TIER = :guarded
      DESCRIPTION = "Find trusted dictionary, etymology and language-authority references for meaning, usage, grammar, idioms, register and pragmatics. Returns sources, not an automatic linguistic verdict.".freeze
      MAX_TERM_CHARS = 100
      MAX_RESULTS = 5
      FOCUSES = %w[meaning etymology usage grammar idiom register pragmatics].freeze
      SOURCES = {
        "nb" => %w[ordbokene.no naob.no sprakradet.no],
        "nn" => %w[ordbokene.no sprakradet.no],
        "en" => %w[dictionary.cambridge.org etymonline.com collinsdictionary.com],
        "auto" => %w[ordbokene.no naob.no sprakradet.no dictionary.cambridge.org etymonline.com collinsdictionary.com],
      }.freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
        @search = WebSearch.new(governor:, event_bus:)
      end

      def call(term:, language: "auto", focus: "meaning", limit: 4)
        subject = term.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip[0, MAX_TERM_CHARS].to_s
        return Result.err("linguist: provide a word or phrase to study", category: :validation) if subject.empty?

        language = SOURCES.key?(language.to_s) ? language.to_s : "auto"
        focus = FOCUSES.include?(focus.to_s) ? focus.to_s : "meaning"
        count = limit.to_i.clamp(1, MAX_RESULTS)
        permission = @governor.permit?(NAME, TIER, "#{language} #{focus} #{subject}")
        return permission if permission.err?

        query = search_query(subject, language:, focus:)
        result = @search.call(query:)
        return result if result.err?

        rows = parse_results(result.value!.to_s, language:)
        return Result.err("linguist: no trusted dictionary or language-authority results found for #{subject.inspect}", category: :provider_error) if rows.empty?

        output = rows.first(count).each_with_index.map do |row, index|
          [ "#{index + 1}. #{row[:title]}", row[:url], row[:snippet] ].reject(&:empty?).join("\n")
        end.join("\n\n")
        @bus&.publish("tool:after", tool: NAME, language:, focus:, count: [rows.length, count].min)
        Result.ok("Linguistic reference for #{subject.inspect} (#{language}, #{focus}):\n\n#{output}\n\nTreat dictionary entries as evidence for meaning and usage; pragmatic intent still depends on context.")
      rescue StandardError => e
        Result.err("linguist: #{e.class}: #{e.message.lines.first.to_s.strip[0, 180]}", category: :infrastructure)
      end

      private

      def search_query(term, language:, focus:)
        domains = SOURCES.fetch(language)
        domain_query = domains.map { |domain| "site:#{domain}" }.join(" OR ")
        "#{term} #{focus} (#{domain_query})"
      end

      def parse_results(text, language:)
        allowed = SOURCES.fetch(language)
        text.to_s.split(/\n{2,}/).filter_map do |block|
          lines = block.lines.map(&:strip).reject(&:empty?)
          raw_url = lines.find { |line| line.start_with?("http://", "https://") }
          next unless raw_url

          uri = URI.parse(raw_url)
          host = uri.host.to_s.downcase.sub(/\Awww\./, "")
          next unless allowed.include?(host)
          next unless uri.scheme == "https" && uri.port == 443 && uri.userinfo.nil?

          title = lines.first.to_s.sub(/\A\d+\.\s*/, "")
          snippet = lines[(lines.index(raw_url) || 0) + 1].to_s
          { title: title.empty? ? host : title, url: uri.to_s, snippet: snippet[0, 300] }
        rescue URI::InvalidURIError
          nil
        end.uniq { |row| row[:url] }
      end
    end
  end
end
