# frozen_string_literal: true

require "json"
require "time"

module MASTER
  module Logging
    # Structured - JSON and human-readable structured logging
    module Structured
      extend self

      LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

      @level = :info
      @format = :human
      @output = $stderr

      class << self
        attr_accessor :format, :output
        attr_reader :level

        def level=(val)
          @level = val.to_sym
        end

        # Write a structured log entry
        # @param severity [Symbol] Log level (:debug, :info, :warn, :error, :fatal)
        # @param message [String] Log message
        # @param context [Hash] Additional key-value context
        def log(severity, message, **context)
          return if LEVELS[severity].nil?
          return if LEVELS[severity] < LEVELS[@level]

          entry = build_entry(severity, message, context)

          case @format
          when :json
            @output.puts(JSON.generate(entry))
          else
            @output.puts(format_human(entry))
          end
        end

        private

        def build_entry(severity, message, context)
          {
            timestamp: Time.now.utc.iso8601(3),
            level: severity.to_s.upcase,
            message: message,
            request_id: Thread.current[:master_request_id],
            **context.compact,
          }.compact
        end

        def format_human(entry)
          prefix = case entry[:level]
                   when "DEBUG" then "\e[37m"    # gray
                   when "INFO"  then "\e[36m"    # cyan
                   when "WARN"  then "\e[33m"    # yellow
                   when "ERROR" then "\e[31m"    # red
                   when "FATAL" then "\e[31;1m" # bold red
                   else ""
                   end
          reset = "\e[0m"

          ctx = entry.except(:timestamp, :level, :message, :request_id)
          ctx_str = ctx.any? ? " #{ctx.map { |k, v| "#{k}=#{v}" }.join(' ')}" : ""
          rid_str = entry[:request_id] ? "[#{entry[:request_id][0..7]}] " : ""

          "#{prefix}#{entry[:level][0]}#{reset} #{rid_str}#{entry[:message]}#{ctx_str}"
        end
      end
    end
  end
end
