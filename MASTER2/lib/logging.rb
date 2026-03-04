# frozen_string_literal: true

require "json"
require "time"
require "securerandom"
require_relative "logging/dmesg"
require_relative "logging/structured"

module MASTER
  # Logging - Unified logging system
  # Combines three logging approaches:
  #   1. Standard logging (debug/info/warn/error) - from log.rb
  #   2. Structured JSON logging - delegated to logging/structured.rb
  #   3. OpenBSD kernel-style dmesg - from dmesg.rb (extracted to logging/dmesg.rb)
  module Logging
    # CONFIGURATION

    LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

    # Verbosity levels for output control
    VERBOSITY_DMESG    = 0  # ring buffer only
    VERBOSITY_STANDARD = 1  # normal (default)
    VERBOSITY_DETAILED = 2  # + debug info
    VERBOSITY_TEACHING = 3  # + explanations

    @level = :info
    @format = :human
    @output = $stderr
    @request_id = nil

    # Import dmesg constants for backward compatibility
    SILENT = Dmesg::SILENT
    LLM_ONLY = Dmesg::LLM_ONLY
    ALL_EVENTS = Dmesg::ALL_EVENTS
    FULL_DEBUG = Dmesg::FULL_DEBUG

    class << self
      attr_accessor :format, :output, :request_id
      attr_reader :level

      def level=(val)
        @level = val.to_sym
      end

      # Delegate dmesg methods
      def trace_level
        Dmesg.trace_level
      end

      def enabled?(level = LLM_ONLY)
        Dmesg.enabled?(level)
      end

      def buffer
        Dmesg.buffer
      end

      def dmesg_log(...)
        Dmesg.dmesg_log(...)
      end

      def dump(...)
        Dmesg.dump(...)
      end

      def clear
        Dmesg.clear
      end

      def reset_timer
        Dmesg.reset_timer
      end
      # STANDARD LOGGING (from log.rb + logging.rb)

      def debug(message, **context)
        log(:debug, message, **context)
        dmesg_log("debug0", message: message, level: FULL_DEBUG) if enabled?(FULL_DEBUG)
      end

      def info(message, **context)
        log(:info, message, **context)
        dmesg_log("info0", message: message, level: ALL_EVENTS) if enabled?(ALL_EVENTS)
      end

      def warn(message, **context)
        log(:warn, message, **context)
        dmesg_log("warn0", message: message, level: ALL_EVENTS) if enabled?(ALL_EVENTS)
      end

      def error(message, **context)
        log(:error, message, **context)
        dmesg_log("error0", message: message, level: SILENT)
      end

      def fatal(message, **context)
        log(:fatal, message, **context)
        dmesg_log("fatal0", message: message, level: SILENT)
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

      # Set request ID for tracing through pipeline (Thread.current for thread safety)
      def with_request_id(id = nil)
        old_id = Thread.current[:master_request_id]
        Thread.current[:master_request_id] = id || SecureRandom.hex(8)
        yield
      ensure
        Thread.current[:master_request_id] = old_id
      end

      def request_id
        Thread.current[:master_request_id] || @request_id
      end

      # Format exception with error class, message, and optional backtrace
      def format_error(exception, backtrace_lines: 5)
        error_msg = "#{exception.class.name}: #{exception.message}"
        if exception.backtrace && backtrace_lines > 0
          error_msg += "\n  #{exception.backtrace.first(backtrace_lines).join("\n  ")}"
        end
        error_msg
      end
      # DOMAIN-SPECIFIC LOGGING (from log.rb)

      # Log LLM call with tier/model information
      def llm(tier:, model:, tokens_in: 0, tokens_out: 0, cost: 0, latency: nil)
        details = "#{tokens_in}->#{tokens_out}tok"
        details += " $#{cost.round(4)}" if cost.positive?
        details += " #{latency}ms" if latency
        dmesg_log("models0", parent: tier.to_s, message: "#{model} #{details}", level: ALL_EVENTS)
      end

      # Log LLM error
      def llm_error(tier:, error:)
        msg = error.to_s.gsub(/\s+/, " ")[0..60]
        dmesg_log("models0", parent: tier.to_s, message: "unavailable: #{msg}", level: ALL_EVENTS)
      end

      # Log autonomy event
      def autonomy(subsystem, event, details = nil)
        dmesg_log("autonomy0", parent: subsystem, message: "#{event}#{", #{details}" if details}",
                               level: ALL_EVENTS)
        info("Autonomy event", subsystem: subsystem, event: event, details: details) if structured_enabled?
      end

      # Log circuit breaker event
      def circuit(provider, state)
        dmesg_log("circuit0", parent: "autonomy0", message: "#{provider} #{state}", level: ALL_EVENTS)
        info("Circuit", provider: provider, state: state) if structured_enabled?
      end

      def retry_event(attempt, max, reason)
        dmesg_log("retry0", parent: "autonomy0", message: "attempt #{attempt}/#{max}, #{reason}", level: ALL_EVENTS)
      end

      def fallback(from, to)
        dmesg_log("fallback0", parent: "autonomy0", message: "#{from} -> #{to}", level: LLM_ONLY)
      end

      # Log tool execution
      def tool(name, action, approved: nil)
        approval = if approved.nil?
                     ""
                   else
                     (approved ? ", auto" : ", manual")
                   end
        dmesg_log("tool0", parent: "engine0", message: "#{name} #{action}#{approval}", level: ALL_EVENTS)
        debug("Tool", name: name, action: action, approved: approved) if structured_enabled?
      end

      # Log file operation
      def file(action, path, details = nil)
        dmesg_log("file0", parent: "engine0",
                           message: "#{action} #{File.basename(path)}#{" (#{details})" if details}", level: ALL_EVENTS)
        debug("File", action: action, path: path, details: details) if structured_enabled?
      end

      # Log memory operation
      def memory(action, details)
        dmesg_log("mem0", parent: "agent0", message: "#{action}: #{details}", level: ALL_EVENTS)
        debug("Memory", action: action, details: details) if structured_enabled?
      end

      def prune(before, after)
        dmesg_log("mem0", parent: "agent0", message: "pruned #{before} -> #{after}", level: ALL_EVENTS)
      end

      # Learning events
      def learn(type, details)
        dmesg_log("learn0", parent: "agent0", message: "#{type}: #{details}", level: ALL_EVENTS)
      end

      def skill(name, action)
        dmesg_log("skill0", parent: "learn0", message: "#{name} #{action}", level: ALL_EVENTS)
      end

      # Task events
      def task(id, action, details = nil)
        dmesg_log("task#{id}", parent: "planner0", message: "#{action}#{": #{details}" if details}",
                               level: ALL_EVENTS)
      end

      def goal(name, status)
        dmesg_log("goal0", parent: "planner0", message: "#{status}: #{name[0..40]}", level: LLM_ONLY)
      end

      # Boot complete event
      def boot_complete(duration_ms)
        dmesg_log("boot", message: "#{duration_ms}ms", level: SILENT)
        info("Boot complete", duration_ms: duration_ms) if structured_enabled?
      end

      def llm_call(model:, tokens_in:, tokens_out:, cost:, duration_ms:, success:)
        info("LLM call", model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost,
                         duration_ms: duration_ms, success: success)
      end

      def tool_exec(tool:, args:, duration_ms:, success:, error: nil)
        if success
          debug("Tool executed", tool: tool,
                                 duration_ms: duration_ms)
        else
          warn("Tool failed", tool: tool, error: error,
                              duration_ms: duration_ms)
        end
      end

      # Current verbosity level from environment
      # @return [Integer] verbosity level (0-3)
      def verbosity
        (ENV["MASTER_VERBOSITY"] || 1).to_i
      end

      # Structured logging enabled when MASTER_LOG is not '0'
      # @return [Boolean]
      def structured_enabled?
        @level != :silent && ENV["MASTER_LOG"] != "0" && verbosity >= VERBOSITY_STANDARD
      end

      # Backward-compatible alias
      alias logging_enabled? structured_enabled?

      # Delegate to Structured module for actual log output
      # @param severity [Symbol] Log severity level
      # @param message [String] Log message
      # @param context [Hash] Additional context key-values
      def log(severity, message, **context)
        return unless structured_enabled?

        # Sync format/output settings to Structured module
        Structured.format = @format
        Structured.output = @output
        Structured.level = @level
        Structured.log(severity, message, **context)
      end
    end
  end
  # BACKWARD COMPATIBILITY ALIASES

  # Alias for old Log module
  Log = Logging

  # Alias for old Dmesg module
  Dmesg = Logging
end
