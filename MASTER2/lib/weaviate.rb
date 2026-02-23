# frozen_string_literal: true

require "json"
require "uri"
require "async"
require "async/http/internet"

module MASTER
  # Weaviate - Vector database for semantic memory
  module Weaviate
    NOT_AVAILABLE = "Weaviate not available."

    HOST = ENV["WEAVIATE_HOST"] || "localhost"
    PORT = (ENV["WEAVIATE_PORT"] || 8080).to_i
    SCHEME = ENV["WEAVIATE_SCHEME"] || "http"
    API_KEY = ENV.fetch("WEAVIATE_API_KEY", nil)

    CLASS_NAME = "MasterMemory"

    # Retry configuration
    MAX_RETRIES = 3
    RETRY_BACKOFF_BASE = 2 # seconds, exponential

    class << self
      def available?
        health_check
      rescue StandardError
        false
      end

      def health_check
        status = nil
        Async do |task|
          task.with_timeout(15) do
            internet = Async::HTTP::Internet.new
            begin
              response = internet.get("#{base_url}/v1/.well-known/ready", auth_headers)
              status = response.status
            rescue Errno::ECONNREFUSED, Async::TimeoutError
              # Weaviate not running -- expected in offline environments
            ensure
              internet.close
            end
          end
        rescue Errno::ECONNREFUSED, Async::TimeoutError
          # suppress
        end
        status == 200
      rescue StandardError
        false
      end

      def setup_schema
        schema = {
          class: CLASS_NAME,
          vectorizer: "text2vec-openai",
          moduleConfig: {
            "text2vec-openai" => {
              model: "text-embedding-3-small",
              type: "text",
            },
          },
          properties: [
            { name: "content", dataType: ["text"] },
            { name: "type", dataType: ["string"] },
            { name: "source", dataType: ["string"] },
            { name: "timestamp", dataType: ["date"] },
            { name: "metadata", dataType: ["text"] },
          ],
        }

        post("/v1/schema", schema)
      end

      # Create a custom schema class
      def create_schema(schema_def)
        return Result.err(NOT_AVAILABLE) unless available?

        response = post("/v1/schema", schema_def)

        if response["error"]
          Result.err("Failed to create schema: #{response['error']}")
        else
          Result.ok({ class: schema_def[:class] })
        end
      rescue StandardError => err
        Result.err("Schema creation failed: #{err.message}")
      end

      # Index an object in a specific class
      def index(class_name, properties, vector: nil)
        return Result.err(NOT_AVAILABLE) unless available?

        object = {
          class: class_name,
          properties: properties,
        }
        object[:vector] = vector if vector

        response = post("/v1/objects", object)

        if response["id"]
          Result.ok({ id: response["id"] })
        else
          Result.err("Failed to index: #{response['error'] || 'unknown error'}")
        end
      rescue StandardError => err
        Result.err("Index failed: #{err.message}")
      end

      # Search in a specific class
      def search_class(class_name, query:, limit: 10, filters: {})
        return Result.err(NOT_AVAILABLE) unless available?

        filter_clause = if filters.any?
                          filter_conditions = filters.map do |field, value|
                            "path: [\"#{field}\"], operator: Equal, valueString: \"#{value}\""
                          end.join(", ")
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

        response = post("/v1/graphql", { query: gql })

        if response.dig("data", "Get", class_name)
          results = response["data"]["Get"][class_name]
          Result.ok(results)
        else
          Result.err("Search failed: #{response['errors']&.first&.dig('message') || 'unknown'}")
        end
      rescue StandardError => err
        Result.err("Search failed: #{err.message}")
      end

      def store(content:, type: "chat", source: nil, metadata: {})
        return Result.err(NOT_AVAILABLE) unless available?

        object = {
          class: CLASS_NAME,
          properties: {
            content: content,
            type: type,
            source: source,
            timestamp: Time.now.utc.iso8601,
            metadata: metadata.to_json,
          },
        }

        response = post("/v1/objects", object)

        if response["id"]
          Result.ok({ id: response["id"] })
        else
          Result.err("Failed to store: #{response['error'] || 'unknown error'}")
        end
      rescue StandardError => err
        Result.err("Store failed: #{err.message}")
      end

      def search(query:, limit: 5, type: nil)
        return Result.err(NOT_AVAILABLE) unless available?

        gql = build_search_query(query, limit, type)
        response = post("/v1/graphql", { query: gql })

        if response.dig("data", "Get", CLASS_NAME)
          results = response["data"]["Get"][CLASS_NAME].map do |obj|
            {
              content: obj["content"],
              type: obj["type"],
              source: obj["source"],
              distance: obj["_additional"]["distance"],
            }
          end
          Result.ok(results)
        else
          Result.err("Search failed: #{response['errors']&.first&.dig('message') || 'unknown'}")
        end
      rescue StandardError => err
        Result.err("Search failed: #{err.message}")
      end

      def similar(content:, limit: 5)
        search(query: content, limit: limit)
      end

      def delete(id:)
        status = nil
        Async do |task|
          task.with_timeout(40) do
            internet = Async::HTTP::Internet.new
            begin
              response = internet.delete("#{base_url}/v1/objects/#{CLASS_NAME}/#{id}", auth_headers)
              status = response.status
            ensure
              internet.close
            end
          end
        end
        (200..299).cover?(status)
      rescue StandardError
        false
      end

      private

      def base_url
        "#{SCHEME}://#{HOST}:#{PORT}"
      end

      def auth_headers
        headers = [["Content-Type", "application/json"]]
        headers << ["Authorization", "Bearer #{API_KEY}"] if API_KEY
        headers
      end

      def post(path, body, retries: MAX_RETRIES)
        url = "#{base_url}#{path}"
        last_error = nil

        retries.times do |attempt|
          result = nil
          begin
            Async do |task|
              task.with_timeout(40) do
                internet = Async::HTTP::Internet.new
                begin
                  response = internet.post(url, auth_headers, body.to_json)
                  result = JSON.parse(response.read)
                ensure
                  internet.close
                end
              end
            end
            return result if result
          rescue JSON::ParserError => err
            return { "error" => "Parse error: #{err.message}" }
          rescue Async::TimeoutError, Errno::ECONNREFUSED => err
            last_error = err.message
            sleep(RETRY_BACKOFF_BASE**attempt) if attempt < retries - 1
          end
        end

        { "error" => "Failed after #{retries} retries: #{last_error}" }
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
