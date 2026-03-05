# frozen_string_literal: true

require "json"
require "uri"
require "net/http"

module MASTER
  module Replicate
    # API client - low-level HTTP interaction with Replicate API
    # HTTP client: net/http — avoids async-http getifaddrs permission issues in containers
    module Client
      API_URL        = "https://api.replicate.com/v1/predictions"
      MODELS_API_URL = "https://api.replicate.com/v1/models"

      HTTP_OPEN_TIMEOUT  = (ENV["MASTER_HTTP_OPEN_TIMEOUT"]  || 10).to_i
      HTTP_READ_TIMEOUT  = (ENV["MASTER_HTTP_READ_TIMEOUT"]  || 60).to_i
      REPLICATE_TIMEOUT  = (ENV["MASTER_REPLICATE_TIMEOUT"]  || 300).to_i
      POLL_INTERVAL      = (ENV["MASTER_POLL_INTERVAL"]      || 2).to_i

      module_function

      # Create a new prediction
      def create_prediction(model:, input:)
        body = { input: input }
        # Official models (owner/name) use /v1/models/{owner}/{name}/predictions
        # Version-pinned models use /v1/predictions with a version SHA
        if model&.include?("/") && !model.match?(/[0-9a-f]{40,}/)
          owner, name = model.split("/", 2)
          url = "#{MODELS_API_URL}/#{owner}/#{name}/predictions"
        elsif model
          body[:version] = model
          url = API_URL
        end

        data = http_post(url, body)
        if data&.dig(:id)
          { id: data[:id] }
        else
          { error: data&.dig(:detail) || "Unknown error" }
        end
      rescue StandardError => e
        warn "Replicate: create_prediction error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      MAX_POLL_ATTEMPTS = (ENV["MASTER_MAX_POLLS"] || 150).to_i  # ~5min at 2s interval

      # Wait for prediction to complete (polling loop)
      def wait_for_completion(id, timeout: REPLICATE_TIMEOUT)
        poll_url   = "#{API_URL}/#{id}"
        start_time = Time.now
        attempts   = 0

        loop do
          return { error: "Timeout waiting for generation (#{timeout}s)" } if Time.now - start_time > timeout
          return { error: "Max poll attempts (#{MAX_POLL_ATTEMPTS}) exceeded" } if attempts >= MAX_POLL_ATTEMPTS

          data = http_get(poll_url)
          attempts += 1

          case data&.dig(:status)
          when "succeeded"
            return { id: id, output: data[:output] }
          when "failed", "canceled"
            return { error: data[:error] || "Generation failed" }
          when "processing", "starting", "queued"
            sleep POLL_INTERVAL
          else
            return { error: "Unknown status: #{data&.dig(:status) || 'nil'}" }
          end
        end
      rescue StandardError => e
        warn "Replicate: wait_for_completion error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      # Download file from URL to local path
      def download_file(url, path)
        uri = URI(url)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                                           open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT) do |http|
          http.get(uri.request_uri)
        end
        return false unless response.is_a?(Net::HTTPSuccess)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, response.body)
        true
      rescue StandardError => e
        warn "Replicate: download_file failed for #{url}: #{e.message}"
        false
      end

      def api_token
        ENV["REPLICATE_API_TOKEN"] || ENV["REPLICATE_API_KEY"]
      end

      def http_post(url, body)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{api_token}"
        req["Content-Type"]  = "application/json"
        req.body = body.to_json

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                                           open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT) do |http|
          http.request(req)
        end
        JSON.parse(response.body, symbolize_names: true)
      end

      def http_get(url)
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{api_token}"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                                           open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT) do |http|
          http.request(req)
        end
        JSON.parse(response.body, symbolize_names: true)
      end
    end
  end
end
