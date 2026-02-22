# frozen_string_literal: true

require "json"
require "uri"
require "async"
require "async/http/internet"

module MASTER
  module Replicate
    # API client - low-level HTTP interaction with Replicate API
    # HTTP client: async-http (Falcon ecosystem) — consistent with server stack
    module Client
      API_URL = "https://api.replicate.com/v1/predictions"

      HTTP_OPEN_TIMEOUT  = (ENV["MASTER_HTTP_OPEN_TIMEOUT"]  || 10).to_i
      HTTP_READ_TIMEOUT  = (ENV["MASTER_HTTP_READ_TIMEOUT"]  || 60).to_i
      REPLICATE_TIMEOUT  = (ENV["MASTER_REPLICATE_TIMEOUT"]  || 300).to_i
      POLL_INTERVAL      = (ENV["MASTER_POLL_INTERVAL"]      || 2).to_i

      module_function

      # Create a new prediction
      def create_prediction(model:, input:)
        body = { input: input }
        # Use 'model' key for owner/name format; 'version' key for SHA-pinned versions
        if model&.include?("/")
          body[:model] = model
        elsif model
          body[:version] = model
        end

        data = nil
        Async do |task|
          task.with_timeout(HTTP_OPEN_TIMEOUT + HTTP_READ_TIMEOUT) do
            internet = Async::HTTP::Internet.new
            begin
              response = internet.post(
                API_URL,
                [
                  ["Authorization", "Bearer #{Replicate.api_key}"],
                  ["Content-Type",  "application/json"],
                ],
                body.to_json,
              )
              data = JSON.parse(response.read, symbolize_names: true)
            ensure
              internet.close
            end
          end
        end

        if data&.dig(:id)
          { id: data[:id] }
        else
          { error: data&.dig(:detail) || "Unknown error" }
        end
      rescue Async::TimeoutError
        { error: "Request timed out" }
      rescue StandardError => e
        $stderr.puts "Replicate: create_prediction error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      # Wait for prediction to complete (polling loop)
      def wait_for_completion(id, timeout: REPLICATE_TIMEOUT)
        poll_url = "#{API_URL}/#{id}"
        start_time = Time.now
        auth_header = [["Authorization", "Bearer #{Replicate.api_key}"]]

        loop do
          return { error: "Timeout waiting for generation" } if Time.now - start_time > timeout

          data = nil
          Async do |task|
            task.with_timeout(HTTP_OPEN_TIMEOUT + HTTP_READ_TIMEOUT) do
              internet = Async::HTTP::Internet.new
              begin
                response = internet.get(poll_url, auth_header)
                data = JSON.parse(response.read, symbolize_names: true)
              ensure
                internet.close
              end
            end
          end

          case data&.dig(:status)
          when "succeeded"
            return { id: id, output: data[:output] }
          when "failed", "canceled"
            return { error: data[:error] || "Generation failed" }
          when "processing", "starting"
            sleep POLL_INTERVAL
          else
            return { error: "Unknown status: #{data&.dig(:status)}" }
          end
        rescue Async::TimeoutError
          return { error: "Poll request timed out" }
        end
      rescue StandardError => e
        $stderr.puts "Replicate: wait_for_completion error: #{e.class} - #{e.message}"
        { error: e.message }
      end

      # Download file from URL to local path
      def download_file(url, path)
        content = nil
        Async do |task|
          task.with_timeout(HTTP_READ_TIMEOUT) do
            internet = Async::HTTP::Internet.new
            begin
              response = internet.get(url)
              content = response.read if response.status == 200
            ensure
              internet.close
            end
          end
        end

        return false unless content

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, content)
        true
      rescue StandardError => e
        $stderr.puts "Replicate: download_file failed for #{url}: #{e.message}"
        false
      end
    end
  end
end
