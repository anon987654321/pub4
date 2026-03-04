# frozen_string_literal: true

require "json"
require "time"
require "securerandom"

module Logging
  module Structured
    TIMESTAMP_FORMAT = :iso8601
    DEFAULT_LEVEL = "INFO"
    RESERVED_KEYS = %w[
      timestamp
      level
      message
      event
      context
      request_id
      pid
      tid
      logger
    ].freeze

    class Logger
      def initialize(io: $stdout, logger_name: nil, level: DEFAULT_LEVEL)
        @io = io
        @logger_name = logger_name
        @level = level
      end

      attr_accessor :level

      def info(message = nil, **fields, &block)
        log("INFO", message, **fields, &block)
      end

      def warn(message = nil, **fields, &block)
        log("WARN", message, **fields, &block)
      end

      def error(message = nil, **fields, &block)
        log("ERROR", message, **fields, &block)
      end

      def debug(message = nil, **fields, &block)
        log("DEBUG", message, **fields, &block)
      end

      def log(level, message = nil, **fields)
        msg = message || (block_given? ? yield : nil)
        event = build_event(level, msg, fields)
        write_event(event)
        event
      end

      private

      def build_event(level, message, fields)
        now = Time.now.utc
        timestamp = format_timestamp(now)

        base = {
          "timestamp" => timestamp,
          "level" => level,
          "message" => message,
          "pid" => Process.pid,
          "tid" => Thread.current.object_id
        }

        base["logger"] = @logger_name if @logger_name
        base.merge!(extract_context(fields))
        base.merge!(sanitize_fields(fields))
        base
      end

      def format_timestamp(time)
        case TIMESTAMP_FORMAT
        when :iso8601
          time.iso8601(6)
        else
          time.to_s
        end
      end

      def extract_context(fields)
        ctx = fields.delete(:context) || fields.delete("context")
        return {} unless ctx

        { "context" => normalize_context(ctx) }
      end

      def normalize_context(ctx)
        return ctx if ctx.is_a?(Hash)

        { "value" => ctx }
      end

      def sanitize_fields(fields)
        out = {}

        fields.each do |k, v|
          key = k.to_s
          out[key] = v unless RESERVED_KEYS.include?(key)
        end

        out
      end

      def write_event(event)
        json = JSON.generate(event)
        @io.write(json)
        @io.write("\n")
      end
    end

    def self.build(io: $stdout, logger_name: nil, level: DEFAULT_LEVEL)
      Logger.new(io: io, logger_name: logger_name, level: level)
    end

    def self.request_id
      SecureRandom.uuid
    end
  end
end