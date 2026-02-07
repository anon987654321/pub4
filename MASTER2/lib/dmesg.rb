# frozen_string_literal: true

module MASTER
  # Dmesg - OpenBSD-inspired kernel message logging
  # Progressive disclosure via MASTER_TRACE levels (Yugen principle)
  #   0 = silent (default)
  #   1 = llm calls only
  #   2 = all events
  #   3 = full debug with timestamps
  module Dmesg
    extend self

    @buffer = []
    @start_time = Time.now

    # Trace levels
    SILENT = 0
    LLM_ONLY = 1
    ALL_EVENTS = 2
    FULL_DEBUG = 3

    class << self
      attr_reader :buffer

      def trace_level
        (ENV['MASTER_TRACE'] || '0').to_i
      end

      def enabled?(level = LLM_ONLY)
        trace_level >= level
      end

      # Core logging - OpenBSD dmesg style
      def log(device, parent: nil, message: nil, level: ALL_EVENTS)
        timestamp = ((Time.now - @start_time) * 1000).round

        line = if parent
                 "#{device} at #{parent}#{message ? ": #{message}" : ''}"
               else
                 "#{device}#{message ? ": #{message}" : ''}"
               end

        entry = { time: timestamp, line: line, level: level }
        @buffer << entry

        # Progressive disclosure (Yugen)
        if enabled?(level) && $stdout.tty?
          output = trace_level >= FULL_DEBUG ? "[#{timestamp}ms] #{line}" : line
          puts UI.dim(output)
        end

        line
      end

      # LLM events (level 1 - always visible when tracing)
      def llm(tier, model, tokens_in: 0, tokens_out: 0, cost: 0, latency: nil)
        details = "#{tokens_in}→#{tokens_out}tok"
        details += ", $#{cost.round(4)}" if cost.positive?
        details += ", #{latency}ms" if latency
        log('llm0', parent: tier.to_s, message: "#{model}, #{details}", level: LLM_ONLY)
      end

      def llm_error(tier, error)
        # Errors always visible (Seijaku - calm error reporting)
        msg = error.to_s.gsub(/\s+/, ' ')[0..60]
        log('llm0', parent: tier.to_s, message: "unavailable: #{msg}", level: SILENT)
      end

      # Autonomy events (level 2)
      def autonomy(subsystem, event, details = nil)
        log('autonomy0', parent: subsystem, message: "#{event}#{details ? ", #{details}" : ''}", level: ALL_EVENTS)
      end

      def budget(action, amount, remaining)
        log('budget0', parent: 'autonomy0', message: "#{action} $#{amount.round(4)}, $#{remaining.round(4)} remaining", level: ALL_EVENTS)
      end

      def circuit(provider, state)
        log('circuit0', parent: 'autonomy0', message: "#{provider} #{state}", level: ALL_EVENTS)
      end

      def retry_event(attempt, max, reason)
        log('retry0', parent: 'autonomy0', message: "attempt #{attempt}/#{max}, #{reason}", level: ALL_EVENTS)
      end

      def fallback(from, to)
        log('fallback0', parent: 'autonomy0', message: "#{from} → #{to}", level: LLM_ONLY)
      end

      # Learning events (level 2)
      def learn(type, details)
        log('learn0', parent: 'agent0', message: "#{type}: #{details}", level: ALL_EVENTS)
      end

      def skill(name, action)
        log('skill0', parent: 'learn0', message: "#{name} #{action}", level: ALL_EVENTS)
      end

      # Task events (level 2)
      def task(id, action, details = nil)
        log("task#{id}", parent: 'planner0', message: "#{action}#{details ? ": #{details}" : ''}", level: ALL_EVENTS)
      end

      def goal(name, status)
        log('goal0', parent: 'planner0', message: "#{status}: #{name[0..40]}", level: LLM_ONLY)
      end

      # Tool events (level 2)
      def tool(name, action, approved: nil)
        approval = approved.nil? ? '' : (approved ? ', auto' : ', manual')
        log('tool0', parent: 'executor0', message: "#{name} #{action}#{approval}", level: ALL_EVENTS)
      end

      # Memory events (level 2)
      def memory(action, details)
        log('mem0', parent: 'agent0', message: "#{action}: #{details}", level: ALL_EVENTS)
      end

      def prune(before, after)
        log('mem0', parent: 'agent0', message: "pruned #{before} → #{after}", level: ALL_EVENTS)
      end

      # File events (level 2)
      def file(action, path, details = nil)
        log('file0', parent: 'executor0', message: "#{action} #{File.basename(path)}#{details ? " (#{details})" : ''}", level: ALL_EVENTS)
      end

      # Boot complete (always show)
      def boot_complete(duration_ms)
        log('boot', message: "#{duration_ms}ms", level: SILENT)
      end

      # Dump buffer
      def dump(last_n: nil, min_level: SILENT)
        entries = @buffer.select { |e| e[:level] >= min_level }
        entries = entries.last(last_n) if last_n
        entries.map { |e| "[#{e[:time]}ms] #{e[:line]}" }.join("\n")
      end

      def clear
        @buffer.clear
      end

      def reset_timer
        @start_time = Time.now
      end
    end
  end
end
