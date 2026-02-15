# frozen_string_literal: true

require "json"
require "time"

module MASTER
  # Logging - Unified logging system
  # Combines three logging approaches:
  #   1. Standard logging (debug/info/warn/error) - from log.rb
  #   2. Structured JSON logging - from logging.rb
  #   3. OpenBSD kernel-style dmesg - from dmesg.rb
  module Logging
    extend self
    # CONFIGURATION

    LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

    @level = :info
    @format = :human  # :json or :human
    @output = $stderr
    @request_id = nil

    # Dmesg configuration
    @buffer = []
    @buffer_mutex = Mutex.new
    @start_time = Time.now
    BUFFER_CAP = 1000

    # Trace levels (for dmesg-style logging)
    SILENT = 0
    LLM_ONLY = 1
    ALL_EVENTS = 2
    FULL_DEBUG = 3

    class << self
      attr_accessor :level, :format, :output, :request_id
      attr_reader :buffer

      def level=(val)
        @level = val.to_sym
      end

      def trace_level
        (ENV['MASTER_TRACE'] || '0').to_i
      end

      def enabled?(level = LLM_ONLY)
        trace_level >= level
      end
      # STANDARD LOGGING (from log.rb + logging.rb)

      def debug(message, **context)
        log(:debug, message, **context)
        dmesg_log('debug0', message: message, level: FULL_DEBUG) if enabled?(FULL_DEBUG)
      end

      def info(message, **context)
        log(:info, message, **context)
        dmesg_log('info0', message: message, level: ALL_EVENTS) if enabled?(ALL_EVENTS)
      end

      def warn(message, **context)
        log(:warn, message, **context)
        dmesg_log('warn0', message: message, level: ALL_EVENTS) if enabled?(ALL_EVENTS)
      end

      def error(message, **context)
        log(:error, message, **context)
        dmesg_log('error0', message: message, level: SILENT)
      end

      def fatal(message, **context)
        log(:fatal, message, **context)
        dmesg_log('fatal0', message: message, level: SILENT)
      end

      # Track operation duration with automatic timing
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

      # Format exception with error class, message, and optional backtrace
      def format_error(exception, backtrace_lines: 5)
        error_msg = "#{exception.class.name}: #{exception.message}"
        if exception.backtrace && backtrace_lines > 0
          error_msg += "\n  " + exception.backtrace.first(backtrace_lines).join("\n  ")
        end
        error_msg
      end
      # DOMAIN-SPECIFIC LOGGING (from log.rb)

      # Log LLM call with tier/model information
      def llm(tier:, model:, tokens_in: 0, tokens_out: 0, cost: 0, latency: nil)
        details = "#{tokens_in}→#{tokens_out}tok"
        details += ", $#{cost.round(4)}" if cost.positive?
        details += ", #{latency}ms" if latency
        dmesg_log('llm0', parent: tier.to_s, message: "#{model}, #{details}", level: LLM_ONLY)

        if logging_enabled?
          info("LLM call",
            tier: tier,
            model: model,
            tokens_in: tokens_in,
            tokens_out: tokens_out,
            cost: cost,
            latency: latency
          )
        end
      end

      # Log LLM error
      def llm_error(tier:, error:)
        msg = error.to_s.gsub(/\s+/, ' ')[0..60]
        dmesg_log('llm0', parent: tier.to_s, message: "unavailable: #{msg}", level: SILENT)
        error("LLM error", tier: tier, error: error.to_s) if logging_enabled?
      end

      # Log autonomy event
      def autonomy(subsystem, event, details = nil)
        dmesg_log('autonomy0', parent: subsystem, message: "#{event}#{details ? ", #{details}" : ''}", level: ALL_EVENTS)
        if logging_enabled?
          info("Autonomy event", subsystem: subsystem, event: event, details: details)
        end
      end

      # Log budget event
      def budget(action, amount, remaining)
        dmesg_log('budget0', parent: 'autonomy0', message: "#{action} $#{amount.round(4)}, $#{remaining.round(4)} remaining", level: ALL_EVENTS)
        if logging_enabled?
          info("Budget event", action: action, amount: amount, remaining: remaining)
        end
      end

      # Log circuit breaker event
      def circuit(provider, state)
        dmesg_log('circuit0', parent: 'autonomy0', message: "#{provider} #{state}", level: ALL_EVENTS)
        info("Circuit", provider: provider, state: state) if logging_enabled?
      end

      def retry_event(attempt, max, reason)
        dmesg_log('retry0', parent: 'autonomy0', message: "attempt #{attempt}/#{max}, #{reason}", level: ALL_EVENTS)
      end

      def fallback(from, to)
        dmesg_log('fallback0', parent: 'autonomy0', message: "#{from} → #{to}", level: LLM_ONLY)
      end

      # Log tool execution
      def tool(name, action, approved: nil)
        approval = approved.nil? ? '' : (approved ? ', auto' : ', manual')
        dmesg_log('tool0', parent: 'executor0', message: "#{name} #{action}#{approval}", level: ALL_EVENTS)
        if logging_enabled?
          debug("Tool", name: name, action: action, approved: approved)
        end
      end

      # Log file operation
      def file(action, path, details = nil)
        dmesg_log('file0', parent: 'executor0', message: "#{action} #{File.basename(path)}#{details ? " (#{details})" : ''}", level: ALL_EVENTS)
        if logging_enabled?
          debug("File", action: action, path: path, details: details)
        end
      end

      # Log memory operation
      def memory(action, details)
        dmesg_log('mem0', parent: 'agent0', message: "#{action}: #{details}", level: ALL_EVENTS)
        debug("Memory", action: action, details: details) if logging_enabled?
      end

      def prune(before, after)
        dmesg_log('mem0', parent: 'agent0', message: "pruned #{before} → #{after}", level: ALL_EVENTS)
      end

      # Learning events
      def learn(type, details)
        dmesg_log('learn0', parent: 'agent0', message: "#{type}: #{details}", level: ALL_EVENTS)
      end

      def skill(name, action)
        dmesg_log('skill0', parent: 'learn0', message: "#{name} #{action}", level: ALL_EVENTS)
      end

      # Task events
      def task(id, action, details = nil)
        dmesg_log("task#{id}", parent: 'planner0', message: "#{action}#{details ? ": #{details}" : ''}", level: ALL_EVENTS)
      end

      def goal(name, status)
        dmesg_log('goal0', parent: 'planner0', message: "#{status}: #{name[0..40]}", level: LLM_ONLY)
      end

      # Boot complete event
      def boot_complete(duration_ms)
        dmesg_log('boot', message: "#{duration_ms}ms", level: SILENT)
        info("Boot complete", duration_ms: duration_ms) if logging_enabled?
      end
      # CONVENIENCE METHODS (from logging.rb)

      # Convenience: log LLM calls (alternative signature)
      def llm_call(model:, tokens_in:, tokens_out:, cost:, duration_ms:, success:)
        info("LLM call",
             model: model,
             tokens_in: tokens_in,
             tokens_out: tokens_out,
             cost: cost,
             duration_ms: duration_ms,
             success: success)
      end

      # Convenience: log tool executions (alternative signature)
      def tool_exec(tool:, args:, duration_ms:, success:, error: nil)
        if success
          debug("Tool executed", tool: tool, duration_ms: duration_ms)
        else
          warn("Tool failed", tool: tool, error: error, duration_ms: duration_ms)
        end
      end
      # DMESG-STYLE LOGGING (from dmesg.rb)

      # Core dmesg logging - OpenBSD kernel style
      def dmesg_log(device, parent: nil, message: nil, level: ALL_EVENTS)
        timestamp = ((Time.now - @start_time) * 1000).round

        line = if parent
                 "#{device} at #{parent}#{message ? ": #{message}" : ''}"
               else
                 "#{device}#{message ? ": #{message}" : ''}"
               end

        entry = { time: timestamp, line: line, level: level }
        @buffer_mutex.synchronize do
          @buffer << entry
          @buffer.shift if @buffer.size > BUFFER_CAP  # Cap buffer size
        end

        # Progressive disclosure (Yugen)
        if enabled?(level) && $stdout.tty?
          output = trace_level >= FULL_DEBUG ? "[#{timestamp}ms] #{line}" : line
          if defined?(UI) && UI.respond_to?(:dim)
            puts UI.dim(output)
          else
            puts output
          end
        end

        line
      end

      # Dump buffer
      def dump(last_n: nil, min_level: SILENT)
        entries = @buffer_mutex.synchronize { @buffer.select { |e| e[:level] >= min_level } }
        entries = entries.last(last_n) if last_n
        entries.map { |e| "[#{e[:time]}ms] #{e[:line]}" }.join("\n")
      end

      def clear
        @buffer_mutex.synchronize { @buffer.clear }
      end

      def reset_timer
        @start_time = Time.now
      end

      private
      # PRIVATE HELPERS

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

      # Check if structured logging is enabled
      def logging_enabled?
        @level != :silent && ENV['MASTER_LOG'] != '0'
      end
    end
  end
  # BACKWARD COMPATIBILITY ALIASES

  # Alias for old Log module
  Log = Logging

  # Alias for old Dmesg module
  Dmesg = Logging
end
