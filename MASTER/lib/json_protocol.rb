#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module MASTER
  # JSON protocol for Unix pipeline communication
  # Every bin executable uses this to read from stdin and write to stdout
  module Protocol
    class << self
      # Read JSON from stdin
      # Returns a hash with symbolized keys
      # Returns empty hash if no input or invalid JSON
      def read
        input = $stdin.read
        return {} if input.nil? || input.strip.empty?
        
        JSON.parse(input, symbolize_names: true)
      rescue JSON::ParserError => e
        { error: "Invalid JSON: #{e.message}", raw: input }
      end

      # Write JSON to stdout
      # Flushes immediately for streaming
      def write(data)
        $stdout.puts(JSON.generate(data))
        $stdout.flush
      end

      # Convenience method: read, transform, write
      # Usage:
      #   Protocol.pipe do |input|
      #     { result: input[:text].upcase }
      #   end
      def pipe
        data = read
        result = yield(data)
        write(result)
      rescue StandardError => e
        write(error: e.message, backtrace: e.backtrace.first(5))
        exit 1
      end

      # Read and merge additional data
      # Useful for pipeline stages that add to existing data
      def merge(additional_data)
        data = read
        data.merge(additional_data)
      end

      # Validate required keys in input
      # Returns [valid, missing_keys]
      def validate_keys(data, *required)
        missing = required.select { |key| !data.key?(key) }
        [missing.empty?, missing]
      end
    end
  end
end
