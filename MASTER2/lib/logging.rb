# frozen_string_literal: true

require "json"
require "time"

module MASTER
  # Logging - Structured logging for production observability
  # Outputs JSON logs for aggregation, human-readable for development
  module Logging
    extend self

    LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze
    
    @level = :info
    @format = :human  # :json or :human
    @output = $stderr
    @request_id = nil

    class << self
      attr_accessor :level, :format, :output, :request_id

      def level=(val)
        @level = val.to_sym
      end

      def debug(message, **context)
        log(:debug, message, **context)
      end

      def info(message, **context)
        log(:info, message, **context)
      end

      def warn(message, **context)
        log(:warn, message, **context)
      end

      def error(message, **context)
        log(:error, message, **context)
      end

      def fatal(message, **context)
        log(:fatal, message, **context)
      end

      # Track request/operation duration
      def timed(operation, **context)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
        
        info("#{operation} completed", duration_ms: duration_ms, **context)
        result
      rescue StandardError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
        error("#{operation} failed", duration_ms: duration_ms, error: e.message, **context)
        raise
      end

      # Set request ID for tracing through pipeline
      def with_request_id(id = nil)
        old_id = @request_id
        @request_id = id || SecureRandom.hex(8)
        yield
      ensure
        @request_id = old_id
      end

      private

      def log(severity, message, **context)
        return if LEVELS[severity] < LEVELS[@level]

        entry = build_entry(severity, message, context)
        
        case @format
        when :json
          @output.puts(JSON.generate(entry))
        else
          @output.puts(format_human(entry))
        end
      end

      def build_entry(severity, message, context)
        {
          timestamp: Time.now.utc.iso8601(3),
          level: severity.to_s.upcase,
          message: message,
          request_id: @request_id,
          **context.compact
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

    # Convenience: log LLM calls
    def self.llm_call(model:, tokens_in:, tokens_out:, cost:, duration_ms:, success:)
      info("LLM call",
           model: model,
           tokens_in: tokens_in,
           tokens_out: tokens_out,
           cost: cost,
           duration_ms: duration_ms,
           success: success)
    end

    # Convenience: log tool executions
    def self.tool_exec(tool:, args:, duration_ms:, success:, error: nil)
      if success
        debug("Tool executed", tool: tool, duration_ms: duration_ms)
      else
        warn("Tool failed", tool: tool, error: error, duration_ms: duration_ms)
      end
    end
  end
end
