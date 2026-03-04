# frozen_string_literal: true

%w[json net/http uri openssl].each { |lib| require lib }

module Harvester
  GITHUB_API_BASE = "https://api.github.com"
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100
  ACCEPT_HEADER = "application/vnd.github+json"
  USER_AGENT = "Harvester"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20

  class Client
    def initialize(access_token: ENV["GITHUB_TOKEN"], http_adapter: Net::HTTP)
      @access_token = access_token.to_s.strip
      @http_adapter = http_adapter
    end

    def harvest(query:, limit: 200, per_page: DEFAULT_PER_PAGE)
      return { repositories: [], errors: ["query is required"] } if query.to_s.strip.empty?

      page_size = [[per_page.to_i, 1].max, MAX_PER_PAGE].min
      target_count = [limit.to_i, 0].max

      repositories = []
      errors = []
      page = 1

      while repositories.size < target_count
        page_result = search_repos(query: query, per_page: page_size, page: page)
        errors.concat(Array(page_result[:errors]))
        repositories.concat(Array(page_result[:repositories]))
        break if page_result[:incomplete] || Array(page_result[:repositories]).empty?

        page += 1
      end

      repositories = repositories.first(target_count) if target_count.positive?
      { repositories: repositories, errors: errors.uniq }
    end

    def search_repos(query:, per_page: DEFAULT_PER_PAGE, page: 1)
      return { repositories: [], errors: ["query is required"], incomplete: true } if query.to_s.strip.empty?

      params = { q: query, per_page: per_page, page: page }
      payload = github_request("/search/repositories", params: params)

      return payload if payload[:errors].any?

      items = Array(payload[:data]["items"])
      { repositories: items, errors: [], incomplete: payload[:data]["incomplete_results"] == true }
    end

    def repo_info(full_name)
      slug = full_name.to_s.strip
      return { repository: nil, errors: ["full_name is required"] } if slug.empty?

      payload = github_request("/repos/#{URI.encode_www_form_component(slug)}")
      return payload if payload[:errors].any?

      { repository: payload[:data], errors: [] }
    end

    def preload_owners(repositories_relation)
      return repositories_relation unless repositories_relation.respond_to?(:includes)

      repositories_relation.includes(:owner)
    end

    private

    def github_request(path, params: {})
      uri = build_uri(path, params)
      request = Net::HTTP::Get.new(uri)
      apply_headers(request)

      response = perform_http_request(uri, request)
      return { data: nil, errors: ["network error: #{response.message}"] } if response.is_a?(StandardError)

      parse_github_response(response)
    end

    def build_uri(path, params)
      uri = URI.join(GITHUB_API_BASE, path)
      query = URI.encode_www_form(params.to_h)
      uri.query = query unless query.empty?
      uri
    end

    def apply_headers(request)
      request["Accept"] = ACCEPT_HEADER
      request["User-Agent"] = USER_AGENT
      request["Authorization"] = "Bearer #{@access_token}" unless @access_token.empty?
    end

    def perform_http_request(uri, request)
      http = @http_adapter.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      http.request(request)
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
      e
    end

    def parse_github_response(response)
      status_code = response.code.to_i
      body = response.body.to_s

      json = begin
        body.empty? ? {} : JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      if (200..299).cover?(status_code)
        return { data: json, errors: [] }
      end

      message = json.is_a?(Hash) ? (json["message"] || "HTTP #{status_code}") : "HTTP #{status_code}"
      { data: nil, errors: [message] }
    end
  end
end