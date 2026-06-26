# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Reach
    # Thin Replicate predictions client — shared by VideoChain; mirrors DEPLOY/repligen.rb API shape.
    class ReplicateClient
      CONFIG_PATH = File.expand_path("~/.config/repligen/config.json").freeze
      BASE = "https://api.replicate.com/v1"

      def initialize(token: nil)
        @token = token || self.class.load_token
        raise ArgumentError, "missing REPLICATE_API_TOKEN" if @token.to_s.strip.empty?
      end

      def self.load_token
        token = ENV["REPLICATE_API_TOKEN"].to_s.strip
        return token unless token.empty?

        token = ENV["REPLICATE_API_KEY"].to_s.strip
        return token unless token.empty?

        return JSON.parse(File.read(CONFIG_PATH))["api_token"].to_s.strip if File.exist?(CONFIG_PATH)

        ""
      rescue StandardError
        ""
      end

      def predict(model_id, input, timeout: 600)
        version = latest_version(model_id)
        pred = post(URI("#{BASE}/predictions"), { version: version, input: input })
        wait_for(pred["id"], timeout: timeout)
      end

      private

      def latest_version(model_id)
        owner, name = model_id.split("/")
        model = get(URI("#{BASE}/models/#{owner}/#{name}"))
        model.dig("latest_version", "id") || raise("no version for #{model_id}")
      end

      def get(uri)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Token #{@token}"
        request(req, uri)
      end

      def post(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "application/json"
        req.body = body.to_json
        request(req, uri)
      end

      def request(req, uri)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
          http.request(req)
        end
        raise "Replicate API #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end

      def wait_for(id, timeout:)
        start = Time.now
        loop do
          pred = get(URI("#{BASE}/predictions/#{id}"))
          case pred["status"]
          when "succeeded" then return pred["output"]
          when "failed" then raise "prediction failed: #{pred['error']}"
          when "canceled" then raise "prediction canceled"
          end
          raise "prediction timeout after #{timeout}s" if Time.now - start > timeout
          sleep 3
        end
      end
    end
  end
end