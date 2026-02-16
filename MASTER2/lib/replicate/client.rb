# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module MASTER
  module Replicate
    # API client - low-level HTTP interaction with Replicate API
    module Client
      API_URL = "https://api.replicate.com/v1/predictions"

      # Timeout constants
      HTTP_OPEN_TIMEOUT = (ENV["MASTER_HTTP_OPEN_TIMEOUT"] || 10).to_i
      HTTP_READ_TIMEOUT = (ENV["MASTER_HTTP_READ_TIMEOUT"] || 60).to_i
      REPLICATE_TIMEOUT = (ENV["MASTER_REPLICATE_TIMEOUT"] || 300).to_i
      POLL_INTERVAL = (ENV["MASTER_POLL_INTERVAL"] || 2).to_i

      module_function

      # Create a new prediction
      def create_prediction(model:, input:)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = HTTP_OPEN_TIMEOUT
        http.read_timeout = HTTP_READ_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{Replicate.api_key}"
        request["Content-Type"] = "application/json"

        body = { input: input }
        body[:version] = model if model
        request.body = body.to_json

        response = http.request(request)
        data = JSON.parse(response.body, symbolize_names: true)

        if data[:id]
          { id: data[:id] }
        else
          { error: data[:detail] || "Unknown error" }
        end
      rescue Net::OpenTimeout, Net::ReadTimeout
        { error: "Request timed out" }
      rescue StandardError => e
        $stderr.puts "Replicate: create_prediction error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      # Wait for prediction to complete
      def wait_for_completion(id, timeout: REPLICATE_TIMEOUT)
        uri = URI("#{API_URL}/#{id}")
        start_time = Time.now
        max_polls = (timeout / POLL_INTERVAL).to_i

        max_polls.times do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = HTTP_OPEN_TIMEOUT
          http.read_timeout = HTTP_READ_TIMEOUT

          request = Net::HTTP::Get.new(uri)
          request["Authorization"] = "Bearer #{Replicate.api_key}"

          response = http.request(request)
          data = JSON.parse(response.body, symbolize_names: true)

          case data[:status]
          when "succeeded"
            return { id: id, output: data[:output] }
          when "failed", "canceled"
            return { error: data[:error] || "Generation failed" }
          when "processing", "starting"
            sleep POLL_INTERVAL
          else
            return { error: "Unknown status: #{data[:status]}" }
          end

          return { error: "Timeout waiting for generation" } if Time.now - start_time > timeout
        end

        { error: "Max polls exceeded" }
      rescue Net::OpenTimeout, Net::ReadTimeout
        { error: "Poll request timed out" }
      rescue StandardError => e
        $stderr.puts "Replicate: wait_for_completion error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      # Download file from URL to local path
      def download_file(url, path)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")

        response = http.get(uri.path)
        return false unless response.is_a?(Net::HTTPSuccess)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, response.body)
        true
      rescue StandardError => e
        $stderr.puts "Replicate: download_file failed for #{url}: #{e.message}"
        false
      end
    end
  end
end
