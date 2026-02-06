# frozen_string_literal: true

module MASTER
  # Dmesg - OpenBSD-inspired kernel message logging
  # Outputs system events in dmesg format: device0 at parent0: description
  module Dmesg
    extend self

    # Bold green for trace output
    TRACE_COLOR = "\e[1;32m"  # Bold green
    RESET = "\e[0m"

    @buffer = []
    @enabled = true
    @start_time = Time.now

    class << self
      attr_accessor :enabled
      attr_reader :buffer

      # Core logging - OpenBSD dmesg style
      def log(device, parent: nil, message: nil)
        return unless @enabled

        timestamp = ((Time.now - @start_time) * 1000).round
        
        line = if parent
          "#{device} at #{parent}#{message ? ": #{message}" : ''}"
        else
          "#{device}#{message ? ": #{message}" : ''}"
        end

        entry = { time: timestamp, line: line }
        @buffer << entry
        
        # Print in bold green if TTY
        if $stdout.tty? && ENV['MASTER_TRACE'] != '0'
          puts "#{TRACE_COLOR}#{line}#{RESET}"
        end
        
        line
      end

      # Autonomy events
      def autonomy(subsystem, event, details = nil)
        log("autonomy0", parent: subsystem, message: "#{event}#{details ? ", #{details}" : ''}")
      end

      def budget(action, amount, remaining)
        log("budget0", parent: "autonomy0", message: "#{action} $#{amount.round(4)}, $#{remaining.round(4)} remaining")
      end

      def circuit(provider, state)
        log("circuit0", parent: "autonomy0", message: "#{provider} #{state}")
      end

      def retry_event(attempt, max, reason)
        log("retry0", parent: "autonomy0", message: "attempt #{attempt}/#{max}, #{reason}")
      end

      def fallback(from, to)
        log("fallback0", parent: "autonomy0", message: "#{from} -> #{to}")
      end

      # LLM events
      def llm(tier, model, tokens_in: 0, tokens_out: 0, cost: 0, latency: nil)
        details = "#{tokens_in}▸#{tokens_out}tok"
        details += ", $#{cost.round(4)}" if cost > 0
        details += ", #{latency}ms" if latency
        log("llm0", parent: tier.to_s, message: "#{model}, #{details}")
      end

      def llm_error(tier, error)
        log("llm0", parent: tier.to_s, message: "error: #{error[0..60]}")
      end

      # Learning events
      def learn(type, details)
        log("learn0", parent: "agent0", message: "#{type}: #{details}")
      end

      def skill(name, action)
        log("skill0", parent: "learn0", message: "#{name} #{action}")
      end

      # Task events  
      def task(id, action, details = nil)
        log("task#{id}", parent: "planner0", message: "#{action}#{details ? ": #{details}" : ''}")
      end

      def goal(name, status)
        log("goal0", parent: "planner0", message: "#{status}: #{name[0..40]}")
      end

      # Tool events
      def tool(name, action, approved: nil)
        approval = approved.nil? ? '' : (approved ? ', auto-approved' : ', requires approval')
        log("tool0", parent: "executor0", message: "#{name} #{action}#{approval}")
      end

      # Memory events
      def memory(action, details)
        log("mem0", parent: "agent0", message: "#{action}: #{details}")
      end

      def prune(before, after)
        log("mem0", parent: "agent0", message: "pruned #{before} -> #{after} messages")
      end

      # Boot-style header
      def boot_header
        hostname = `hostname`.strip rescue 'localhost'
        lines = []
        lines << "#{MASTER::CODENAME} #{MASTER::VERSION} (GENERIC) #1: #{Time.now.strftime('%a %b %e %H:%M:%S %Z %Y')}"
        lines << "    #{ENV['USER'] || 'master'}@#{hostname}:#{MASTER::ROOT}"
        lines << "mainbus0 at root"
        lines << "cpu0 at mainbus0: #{cpu_info}"
        lines << "ruby0 at mainbus0: ruby #{RUBY_VERSION}"
        lines << "autonomy0 at mainbus0: budget $#{Autonomy.config[:budget_limit]}, circuits #{Autonomy.config[:circuit_breaker_threshold]} threshold"
        lines << "learn0 at autonomy0: few-shot, self-improving, A/B testing"
        lines << "llm0 at autonomy0: #{LLM::TIERS.keys.join(', ')}"
        
        lines.each { |l| puts l } if $stdout.tty?
        lines
      end

      def boot_complete(duration_ms)
        log("boot", message: "complete, #{duration_ms}ms")
      end

      # Dump buffer
      def dump(last_n: nil)
        entries = last_n ? @buffer.last(last_n) : @buffer
        entries.map { |e| "[#{e[:time]}ms] #{e[:line]}" }.join("\n")
      end

      def clear
        @buffer.clear
      end

      private

      def cpu_info
        if RUBY_PLATFORM.include?('openbsd')
          `sysctl -n hw.model`.strip rescue 'unknown'
        elsif File.exist?('/proc/cpuinfo')
          File.read('/proc/cpuinfo').match(/model name\s*:\s*(.+)/)&.[](1) || 'unknown'
        else
          'unknown'
        end
      end
    end
  end
end
