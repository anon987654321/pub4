# Gemfile
gem 'faraday', '~> 2.14'

# lib/my_client.rb
require 'faraday'
require 'logger'
# frozen_string_literal: true

# Thin, opinionated wrapper around Faraday.
# Provides sane defaults, easy extension and a minimal public API.
# Designed for OpenBSD‑first deployments: minimal syscalls, no external C libs.
class MyClient
  # @param base_url [String] Base URL for all requests (e.g. "https://api.example.com")
  # @return [void]
  def initialize(base_url:)
    @conn = Faraday.new(url: base_url) do |faraday|
      # Encode parameters as application/x-www-form-urlencoded (default for GET/POST)
      faraday.request :url_encoded

      # Detailed request/response logging – useful during development and debugging.
      # In production replace the logger or disable it via the `:logger` middleware options.
      faraday.response :logger, Logger.new($stdout), bodies: true, logger_level: :info

      # Default Net::HTTP adapter; replace with :typhoeus, :excon, etc., when needed.
      faraday.adapter Faraday.default_adapter
    end
  end

  # Perform a GET request and return the raw body.
  #
  # @param path   [String] Relative path (e.g. "/api/v1/resource")
  # @param params [Hash]   Optional query parameters (default: {})
  # @return [String]       Response body
  # @raise  [Faraday::Error] for transport errors or non‑2xx HTTP status
  def fetch(path, params = {})
    response = @conn.get(path, params)
    response.raise_for_status # Surface HTTP errors as exceptions
    response.body
  end

  # Example usage:
  #
  #   client = MyClient.new(base_url: "https://api.example.com")
  #   json   = client.fetch("/users", limit: 10)
  #
  # To add retries, JSON handling, or timeout control, extend the middleware stack
  # in `initialize`:
  #
  #   faraday.request :retry, max: 3, interval: 0.5, backoff_factor: 2
  #   faraday.response :json, content_type: /\bjson$/
  #   faraday.options.timeout = 5      # seconds
  #   faraday.options.open_timeout = 2
  #
  # The wrapper is deliberately tiny; callers can build higher‑level abstractions
  # (e.g., service objects) on top of `fetch` without inheriting unnecessary complexity.