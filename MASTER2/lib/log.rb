# frozen_string_literal: true

module MASTER
  # Log - Unified logging facade. Delegates to Dmesg (kernel-style) and Logging (structured JSON).
  # This is the public API — use this instead of calling Dmesg or Logging directly.
  # Combines Dmesg (kernel-style), Logging (structured JSON), and puts statements
  # Provides single interface with progressive disclosure via MASTER_TRACE
  module Log
    extend self

    # Log debug message (level 3)
    # @param msg [String] Message to log
    # @param ctx [Hash] Additional context
    # @return [void]
    def debug(msg, **ctx)
      Dmesg.log('debug0', message: msg, level: Dmesg::FULL_DEBUG) if Dmesg.enabled?(Dmesg::FULL_DEBUG)
      Logging.debug(msg, **ctx) if logging_enabled?
    end

    # Log info message (level 2)
    # @param msg [String] Message to log
    # @param ctx [Hash] Additional context
    # @return [void]
    def info(msg, **ctx)
      Dmesg.log('info0', message: msg, level: Dmesg::ALL_EVENTS) if Dmesg.enabled?(Dmesg::ALL_EVENTS)
      Logging.info(msg, **ctx) if logging_enabled?
    end

    # Log warning message (level 2)
    # @param msg [String] Message to log
    # @param ctx [Hash] Additional context
    # @return [void]
    def warn(msg, **ctx)
      Dmesg.log('warn0', message: msg, level: Dmesg::ALL_EVENTS) if Dmesg.enabled?(Dmesg::ALL_EVENTS)
      Logging.warn(msg, **ctx) if logging_enabled?
    end

    # Log error message (always visible)
    # @param msg [String] Message to log
    # @param ctx [Hash] Additional context
    # @return [void]
    def error(msg, **ctx)
      Dmesg.log('error0', message: msg, level: Dmesg::SILENT)
      Logging.error(msg, **ctx) if logging_enabled?
    end

    # Log fatal error (always visible)
    # @param msg [String] Message to log
    # @param ctx [Hash] Additional context
    # @return [void]
    def fatal(msg, **ctx)
      Dmesg.log('fatal0', message: msg, level: Dmesg::SILENT)
      Logging.fatal(msg, **ctx) if logging_enabled?
    end

    # Log LLM call with tier/model information
    # @param tier [Symbol] LLM tier (:fast, :strong, etc.)
    # @param model [String] Model identifier
    # @param tokens_in [Integer] Input tokens
    # @param tokens_out [Integer] Output tokens
    # @param cost [Float] Cost in dollars
    # @param latency [Integer, nil] Latency in milliseconds
    # @return [void]
    def llm(tier:, model:, tokens_in: 0, tokens_out: 0, cost: 0, latency: nil)
      Dmesg.llm(tier, model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost, latency: latency)
      if logging_enabled?
        Logging.info("LLM call", 
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
    # @param tier [Symbol] LLM tier
    # @param error [StandardError, String] Error message
    # @return [void]
    def llm_error(tier:, error:)
      Dmesg.llm_error(tier, error)
      Logging.error("LLM error", tier: tier, error: error.to_s) if logging_enabled?
    end

    # Log autonomy event
    # @param subsystem [String] Subsystem name
    # @param event [String] Event description
    # @param details [String, nil] Additional details
    # @return [void]
    def autonomy(subsystem, event, details = nil)
      Dmesg.autonomy(subsystem, event, details)
      if logging_enabled?
        Logging.info("Autonomy event", subsystem: subsystem, event: event, details: details)
      end
    end

    # Log budget event
    # @param action [String] Action performed
    # @param amount [Float] Amount spent
    # @param remaining [Float] Amount remaining
    # @return [void]
    def budget(action, amount, remaining)
      Dmesg.budget(action, amount, remaining)
      if logging_enabled?
        Logging.info("Budget event", action: action, amount: amount, remaining: remaining)
      end
    end

    # Log circuit breaker event
    # @param provider [String] Provider name
    # @param state [String] Circuit state (open/closed)
    # @return [void]
    def circuit(provider, state)
      Dmesg.circuit(provider, state)
      Logging.info("Circuit", provider: provider, state: state) if logging_enabled?
    end

    # Log tool execution
    # @param name [String] Tool name
    # @param action [String] Action performed
    # @param approved [Boolean, nil] Approval status
    # @return [void]
    def tool(name, action, approved: nil)
      Dmesg.tool(name, action, approved: approved)
      if logging_enabled?
        Logging.debug("Tool", name: name, action: action, approved: approved)
      end
    end

    # Log file operation
    # @param action [String] Action performed
    # @param path [String] File path
    # @param details [String, nil] Additional details
    # @return [void]
    def file(action, path, details = nil)
      Dmesg.file(action, path, details)
      if logging_enabled?
        Logging.debug("File", action: action, path: path, details: details)
      end
    end

    # Log memory operation
    # @param action [String] Action performed
    # @param details [String] Additional details
    # @return [void]
    def memory(action, details)
      Dmesg.memory(action, details)
      Logging.debug("Memory", action: action, details: details) if logging_enabled?
    end

    # Track operation duration with automatic timing
    # @param operation [String] Operation name
    # @param ctx [Hash] Additional context
    # @yield Block to execute and time
    # @return [Object] Result of the block
    def timed(operation, **ctx)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
      
      info("#{operation} completed", duration_ms: duration_ms, **ctx)
      result
    rescue StandardError => e
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
      error("#{operation} failed", duration_ms: duration_ms, error: e.message, **ctx)
      raise
    end

    # Boot complete event (always visible)
    # @param duration_ms [Integer] Boot duration in milliseconds
    # @return [void]
    def boot_complete(duration_ms)
      Dmesg.boot_complete(duration_ms)
      Logging.info("Boot complete", duration_ms: duration_ms) if logging_enabled?
    end

    private

    # Check if structured logging is enabled
    # @return [Boolean] true if logging should be output
    def logging_enabled?
      Logging.level != :silent && ENV['MASTER_LOG'] != '0'
    end
  end
end
