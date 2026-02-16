# frozen_string_literal: true

module MASTER
  module Logging
    # Dmesg - OpenBSD kernel-style logging
    module Dmesg
      extend self

      @buffer = []
      @buffer_mutex = Mutex.new
      @start_time = Time.now
      BUFFER_CAP = 1000

      SILENT = 0
      LLM_ONLY = 1
      ALL_EVENTS = 2
      FULL_DEBUG = 3

      class << self
        attr_reader :buffer

        def trace_level
          (ENV['MASTER_TRACE'] || '1').to_i
        end

        def enabled?(level = LLM_ONLY)
          trace_level >= level
        end

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
            @buffer.shift if @buffer.size > BUFFER_CAP
          end

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
      end
    end
  end
end
