# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require 'net/http'
require 'uri'

module MASTER
  # Harvester - Ecosystem intelligence gathering
  # Gathers information from open source ecosystems (GitHub, etc.)
  # Ported from MASTER v1, adapted for MASTER2's Result monad
  class Harvester
    GITHUB_API = 'https://api.github.com'
    RATE_LIMIT_DELAY = 1.0 # seconds between requests

    attr_reader :harvested_data, :stats

    def initialize(github_token: nil)
      @github_token = github_token || ENV['GITHUB_TOKEN']
      @harvested_data = []
      @stats = {
        repos_scanned: 0,
        items_found: 0,
        errors: 0,
        started_at: Time.now
      }
    end

    # Search GitHub for repositories
    def search_repos(query, limit: 10)
      uri = URI("#{GITHUB_API}/search/repositories")
      uri.query = URI.encode_www_form(q: query, per_page: limit, sort: 'stars')

      response = github_request(uri)
      return Result.err("Search failed.") unless response

      repos = response['items']&.map do |item|
        {
          name: item['full_name'],
          description: item['description'],
          stars: item['stargazers_count'],
          language: item['language'],
          url: item['html_url']
        }
      end || []

      @stats[:repos_scanned] += repos.size
      Result.ok(repos: repos)
    rescue StandardError => e
      @stats[:errors] += 1
      Result.err("Search failed: #{e.message}")
    end

    # Get repository info
    def get_repo_info(owner, repo)
      uri = URI("#{GITHUB_API}/repos/#{owner}/#{repo}")
      response = github_request(uri)
      return Result.err("Repository not found.") unless response

      info = {
        name: response['full_name'],
        description: response['description'],
        stars: response['stargazers_count'],
        forks: response['forks_count'],
        language: response['language'],
        topics: response['topics'] || [],
        created_at: response['created_at'],
        updated_at: response['updated_at'],
        url: response['html_url']
      }

      @stats[:repos_scanned] += 1
      Result.ok(info)
    rescue StandardError => e
      @stats[:errors] += 1
      Result.err("Failed to get repo info: #{e.message}")
    end

    # Get trending repositories
    def get_trending(language: nil, since: 'daily')
      # Use Web module's GitHub helper if available
      if defined?(Web::GitHub)
        return Web::GitHub.trending(language: language, since: since)
      end

      Result.err("Web::GitHub module not available.")
    end

    # Harvest data from multiple sources
    def harvest(sources: [])
      puts "🌾 Starting ecosystem harvest..."

      sources.each do |source|
        begin
          if source.is_a?(Hash) && source[:owner] && source[:repo]
            puts "  Scanning #{source[:owner]}/#{source[:repo]}..."
            result = get_repo_info(source[:owner], source[:repo])
            @harvested_data << result.value if result.ok?
          elsif source.is_a?(String)
            puts "  Searching: #{source}..."
            result = search_repos(source, limit: 5)
            @harvested_data += result.value[:repos] if result.ok?
          end
        rescue StandardError => e
          puts "  ✗ Error: #{e.message}"
          @stats[:errors] += 1
        end

        sleep RATE_LIMIT_DELAY
      end

      @stats[:completed_at] = Time.now
      @stats[:duration] = (@stats[:completed_at] - @stats[:started_at]).round(2)
      @stats[:items_found] = @harvested_data.size

      puts "\n✓ Harvest complete:"
      puts "  Items: #{@stats[:items_found]}"
      puts "  Duration: #{@stats[:duration]}s"
      puts "  Errors: #{@stats[:errors]}"

      Result.ok(data: @harvested_data, stats: @stats)
    end

    # Save harvested data to YAML
    def save(output_path: nil)
      output_path ||= File.join(Paths.data, "harvested_#{Time.now.strftime('%Y-%m-%d')}.yml")

      FileUtils.mkdir_p(File.dirname(output_path))

      data = {
        metadata: {
          harvested_at: Time.now.iso8601,
          stats: @stats
        },
        data: @harvested_data
      }

      File.write(output_path, YAML.dump(data))
      puts "💾 Saved to: #{output_path}"

      Result.ok(path: output_path)
    rescue StandardError => e
      Result.err("Failed to save: #{e.message}")
    end

    # Analyze trends in harvested data
    def analyze_trends
      return {} if @harvested_data.empty?

      {
        languages: language_distribution,
        avg_stars: average_stars,
        total_items: @harvested_data.size
      }
    end

    private

    def github_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/vnd.github.v3+json'
      request['User-Agent'] = 'MASTER2-Harvester'
      request['Authorization'] = "token #{@github_token}" if @github_token

      response = http.request(request)

      return nil unless response.code.start_with?('2')
      JSON.parse(response.body)
    rescue JSON::ParserError
      nil
    rescue StandardError => e
      puts "  Request error: #{e.message}"
      nil
    end

    def language_distribution
      langs = @harvested_data.map { |d| d[:language] }.compact
      langs.group_by(&:itself).transform_values(&:size).sort_by { |_, v| -v }.to_h
    end

    def average_stars
      stars = @harvested_data.map { |d| d[:stars] }.compact
      return 0 if stars.empty?
      (stars.sum.to_f / stars.size).round(1)
    end
  end
end
