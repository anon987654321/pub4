# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  # Weaviate - Vector database for semantic memory
  module Weaviate
    extend self

    HOST = ENV['WEAVIATE_HOST'] || 'localhost'
    PORT = (ENV['WEAVIATE_PORT'] || 8080).to_i
    SCHEME = ENV['WEAVIATE_SCHEME'] || 'http'

    CLASS_NAME = 'MasterMemory'

    class << self
      def available?
        health_check
      rescue
        false
      end

      def health_check
        uri = URI("#{base_url}/v1/.well-known/ready")
        response = Net::HTTP.get_response(uri)
        response.is_a?(Net::HTTPSuccess)
      rescue
        false
      end

      def setup_schema
        schema = {
          class: CLASS_NAME,
          vectorizer: 'text2vec-openai',
          moduleConfig: {
            'text2vec-openai' => {
              model: 'text-embedding-3-small',
              type: 'text'
            }
          },
          properties: [
            { name: 'content', dataType: ['text'] },
            { name: 'type', dataType: ['string'] },
            { name: 'source', dataType: ['string'] },
            { name: 'timestamp', dataType: ['date'] },
            { name: 'metadata', dataType: ['text'] }
          ]
        }

        post('/v1/schema', schema)
      end

      def store(content:, type: 'chat', source: nil, metadata: {})
        return Result.err("Weaviate not available") unless available?

        object = {
          class: CLASS_NAME,
          properties: {
            content: content,
            type: type,
            source: source,
            timestamp: Time.now.utc.iso8601,
            metadata: metadata.to_json
          }
        }

        response = post('/v1/objects', object)

        if response['id']
          Result.ok({ id: response['id'] })
        else
          Result.err("Failed to store: #{response['error'] || 'unknown error'}")
        end
      rescue => e
        Result.err("Store failed: #{e.message}")
      end

      def search(query:, limit: 5, type: nil)
        return Result.err("Weaviate not available") unless available?

        gql = build_search_query(query, limit, type)
        response = post('/v1/graphql', { query: gql })

        if response.dig('data', 'Get', CLASS_NAME)
          results = response['data']['Get'][CLASS_NAME].map do |obj|
            {
              content: obj['content'],
              type: obj['type'],
              source: obj['source'],
              distance: obj['_additional']['distance']
            }
          end
          Result.ok(results)
        else
          Result.err("Search failed: #{response['errors']&.first&.dig('message') || 'unknown'}")
        end
      rescue => e
        Result.err("Search failed: #{e.message}")
      end

      def similar(content:, limit: 5)
        search(query: content, limit: limit)
      end

      def delete(id:)
        uri = URI("#{base_url}/v1/objects/#{CLASS_NAME}/#{id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        request = Net::HTTP::Delete.new(uri)
        request['Content-Type'] = 'application/json'

        response = http.request(request)
        response.is_a?(Net::HTTPSuccess)
      rescue
        false
      end

      private

      def base_url
        "#{SCHEME}://#{HOST}:#{PORT}"
      end

      def post(path, body)
        uri = URI("#{base_url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = body.to_json

        response = http.request(request)
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'error' => response.body }
      end

      def build_search_query(text, limit, type)
        filter = type ? ", where: { path: [\"type\"], operator: Equal, valueString: \"#{type}\" }" : ""

        <<~GQL
          {
            Get {
              #{CLASS_NAME}(
                nearText: { concepts: ["#{text.gsub('"', '\\"')}"] }
                limit: #{limit}
                #{filter}
              ) {
                content
                type
                source
                _additional {
                  distance
                  id
                }
              }
            }
          }
        GQL
      end
    end
  end
end
