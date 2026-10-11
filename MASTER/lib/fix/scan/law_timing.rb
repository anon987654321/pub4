# frozen_string_literal: true

module Master
  module Fix
    module Scan
      # Seconds spent per law across one scan, summed over every file. Off unless
      # MASTER_SCAN_TIMING=1, because the clock reads cost more than a cheap law.
      module LawTiming
        TOP = 10
        MUTEX = Mutex.new
        TOTALS = Hash.new(0.0)

        module_function

        def enabled? = ENV["MASTER_SCAN_TIMING"] == "1"

        def measure(law)
          return yield unless enabled?

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yield
        ensure
          if started
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            MUTEX.synchronize { TOTALS[label(law)] += elapsed }
          end
        end

        def label(law)
          law.respond_to?(:id) ? law.id.to_s : law.class.name.to_s
        end

        # The slowest laws, as "id 12.3s" strings, and the totals cleared so the
        # next scan in the same process starts from zero.
        def drain(top: TOP)
          MUTEX.synchronize do
            rows = TOTALS.sort_by { |_law, secs| -secs }.first(top).map { |law, secs| "#{law} #{secs.round(1)}s" }
            TOTALS.clear
            rows
          end
        end
      end
    end
  end
end
