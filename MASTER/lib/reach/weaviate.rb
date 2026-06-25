# frozen_string_literal: true

require "net/http"
require "json"

module Master
  module Reach
    class Weaviate
      def initialize(host: ENV.fetch("WEAVIATE_HOST", "http://127.0.0.1:8080"), api_key: ENV["WEAVIATE_API_KEY"])
        @host = host.chomp("/")
        @api_key = api_key
      end

      def indexed?(class_name:, object_id:)
        response = get("/v1/objects/#{class_name}/#{object_id}")
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      def upsert(class_name:, object_id:, properties:, vector: nil)
        body = { class: class_name, id: object_id, properties: properties }
        body[:vector] = vector if vector
        post("/v1/objects", body)
      end

      def search(class_name:, near_text:, limit: 5)
        body = {
          query: "{ Get { #{class_name}(limit: #{limit}, nearText: { concepts: [#{near_text.to_json}] }) { _additional { distance } } } } }"
        }
        post("/v1/graphql", body)
      end

      private

      def get(path)
        request(Net::HTTP::Get, path)
      end

      def post(path, body)
        request(Net::HTTP::Post, path, body)
      end

      def request(klass, path, body = nil)
        uri = URI("#{@host}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 5
        http.open_timeout = 3
        req = klass.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
        req.body = body.to_json if body
        http.request(req)
      end
    end
  end
end