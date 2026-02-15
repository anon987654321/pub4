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
    API_KEY = ENV['WEAVIATE_API_KEY']

    CLASS_NAME = 'MasterMemory'

    # Retry configuration
    MAX_RETRIES = 3
    RETRY_BACKOFF_BASE = 2  # seconds, exponential

    class << self
      def available?
        health_check
      rescue StandardError
        false
      end

      def health_check
        uri = URI("#{base_url}/v1/.well-known/ready")
        request = Net::HTTP::Get.new(uri)
        add_auth_headers(request)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 5
        http.read_timeout = 10
        response = http.request(request)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
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

      # Create a custom schema class
      def create_schema(schema_def)
        return Result.err("Weaviate not available") unless available?

        response = post('/v1/schema', schema_def)

        if response['error']
          Result.err("Failed to create schema: #{response['error']}")
        else
          Result.ok({ class: schema_def[:class] })
        end
      rescue StandardError => e
        Result.err("Schema creation failed: #{e.message}")
      end

      # Index an object in a specific class
      def index(class_name, properties, vector: nil)
        return Result.err("Weaviate not available") unless available?

        object = {
          class: class_name,
          properties: properties
        }
        object[:vector] = vector if vector

        response = post('/v1/objects', object)

        if response['id']
          Result.ok({ id: response['id'] })
        else
          Result.err("Failed to index: #{response['error'] || 'unknown error'}")
        end
      rescue StandardError => e
        Result.err("Index failed: #{e.message}")
      end

      # Search in a specific class
      def search_class(class_name, query:, limit: 10, filters: {})
        return Result.err("Weaviate not available") unless available?

        filter_clause = if filters.any?
          filter_conditions = filters.map do |field, value|
            "path: [\"#{field}\"], operator: Equal, valueString: \"#{value}\""
          end.join(', ')
          ", where: { #{filter_conditions} }"
        else
          ""
        end

        gql = <<~GQL
          {
            Get {
              #{class_name}(
                nearText: { concepts: ["#{query.gsub('"', '\\"')}"] }
                limit: #{limit}
                #{filter_clause}
              ) {
                _additional {
                  distance
                  id
                }
              }
            }
          }
        GQL

        response = post('/v1/graphql', { query: gql })

        if response.dig('data', 'Get', class_name)
          results = response['data']['Get'][class_name]
          Result.ok(results)
        else
          Result.err("Search failed: #{response['errors']&.first&.dig('message') || 'unknown'}")
        end
      rescue StandardError => e
        Result.err("Search failed: #{e.message}")
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
      rescue StandardError => e
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
      rescue StandardError => e
        Result.err("Search failed: #{e.message}")
      end

      def similar(content:, limit: 5)
        search(query: content, limit: limit)
      end

      def delete(id:)
        uri = URI("#{base_url}/v1/objects/#{CLASS_NAME}/#{id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Delete.new(uri)
        request['Content-Type'] = 'application/json'

        response = http.request(request)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      private

      def base_url
        "#{SCHEME}://#{HOST}:#{PORT}"
      end

      def add_auth_headers(request)
        request['Content-Type'] = 'application/json'
        request['Authorization'] = "Bearer #{API_KEY}" if API_KEY
      end

      def post(path, body, retries: MAX_RETRIES)
        uri = URI("#{base_url}#{path}")
        last_error = nil

        retries.times do |attempt|
          begin
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')
            http.open_timeout = 10
            http.read_timeout = 30

            request = Net::HTTP::Post.new(uri)
            add_auth_headers(request)
            request.body = body.to_json

            response = http.request(request)
            return JSON.parse(response.body)
          rescue JSON::ParserError
            return { 'error' => response&.body || 'Parse error' }
          rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
            last_error = e.message
            sleep(RETRY_BACKOFF_BASE ** attempt) if attempt < retries - 1
          end
        end

        { 'error' => "Failed after #{retries} retries: #{last_error}" }
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
