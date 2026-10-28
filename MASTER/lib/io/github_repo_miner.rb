# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Io
    # Ranked discovery of public GitHub repositories. Repository content is
    # untrusted metadata: this adapter never clones or executes repository code.
    class GitHubRepoMiner
      TIER = :guarded
      NAME = "github_repo_miner".freeze
      DESCRIPTION = "Search public GitHub repositories by topic and rank by stars or recent updates; never clones or executes code.".freeze
      ENDPOINT = "https://api.github.com/search/repositories".freeze
      TIMEOUT = 10
      MAX_QUERY_CHARS = 300
      MAX_RESPONSE_BYTES = 2 * 1024 * 1024
      MAX_RESULTS = 10

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(query:, sort: "stars", limit: 5)
        query = normalize_query(query)
        return Result.err("github_repo_miner: provide a repository topic", category: :validation) if query.empty?

        sort = %w[stars updated forks].include?(sort.to_s) ? sort.to_s : "stars"
        limit = [[limit.to_i, 1].max, MAX_RESULTS].min
        perm = @governor.permit?(NAME, TIER, query)
        return perm if perm.err?

        response = fetch_response(query:, sort:, limit:)
        return Result.err("github_repo_miner: HTTP #{response.code}", category: :infrastructure) unless response.code.to_s == "200"

        body = response.body.to_s
        return Result.err("github_repo_miner: response exceeds #{MAX_RESPONSE_BYTES} bytes", category: :validation) if body.bytesize > MAX_RESPONSE_BYTES

        data = JSON.parse(body)
        repositories = Array(data["items"]).first(limit).filter_map { |item| format_repository(item) }
        value = if repositories.empty?
                  "No public GitHub repositories matched #{query.inspect}."
                else
                  repositories.each_with_index.map { |repository, index| format_result(repository, index + 1) }.join("\n\n")
                end
        screened = injection_guard.screen(value, tool: NAME, source: "api.github.com", bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: "api.github.com")
        @bus&.publish("tool:after", tool: NAME, query:, sort:, count: repositories.length)
        Result.ok(screened)
      rescue JSON::ParserError => e
        Result.err("github_repo_miner: invalid GitHub search response (#{e.message})", category: :infrastructure)
      rescue StandardError => e
        Result.err("github_repo_miner: #{e.message}", category: :infrastructure)
      end

      private

      def normalize_query(value)
        query = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip[0, MAX_QUERY_CHARS].to_s
        query = query.sub(/\A(?:please\s+)?(?:find|show|list|recommend|discover|search for)\s+/i, "")
        query = query.gsub(/\b(?:popular|trending|recent|latest|updated|active)\s+(?:github\s+)?(?:repositories|repos|projects|libraries)\b/i, " ")
        query = query.gsub(/\b(?:github\s+)?(?:repositories|repos)\b/i, " ")
        query = query.gsub(/\b(?:on|from)\s+github\b/i, " ")
        query = query.gsub(/\b(?:for|about)\b/i, " ")
        query.gsub(/\s+/, " ").strip
      end

      def fetch_response(query:, sort:, limit:)
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(q: query, sort:, order: "desc", per_page: limit)
        address = SsrfGuard.pinned_address(uri)
        raise "refused internal/reserved address" unless address

        client = SsrfGuard.http_for(uri, address, timeout: TIMEOUT)
        client.start do |http|
          http.get(uri.request_uri, {
            "User-Agent" => "MASTER/1 (github_repo_miner)",
            "Accept" => "application/vnd.github+json",
            "X-GitHub-Api-Version" => "2022-11-28",
          })
        end
      end

      def format_repository(item)
        return unless item.is_a?(Hash)

        name = item["full_name"].to_s
        url = item["html_url"].to_s
        return if name.empty? || !trusted_repository_url?(url)

        {
          name:,
          url:,
          description: item["description"].to_s.gsub(/\s+/, " ").strip[0, 500],
          stars: Integer(item["stargazers_count"] || 0),
          forks: Integer(item["forks_count"] || 0),
          language: item["language"].to_s,
          updated_at: item["updated_at"].to_s,
        }
      rescue ArgumentError, TypeError
        nil
      end

      def trusted_repository_url?(value)
        uri = URI.parse(value)
        uri.is_a?(URI::HTTPS) && uri.host.to_s.downcase == "github.com" && uri.userinfo.nil?
      rescue URI::InvalidURIError
        false
      end

      def format_result(repository, index)
        language = repository[:language].empty? ? "language not reported" : repository[:language]
        lines = [
          "#{index}. #{repository[:name]} (#{repository[:stars]} stars, #{repository[:forks]} forks)",
          repository[:url],
          "Language: #{language}; updated: #{repository[:updated_at]}",
        ]
        lines << "Description: #{repository[:description]}" unless repository[:description].empty?
        lines.join("\n")
      end

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
