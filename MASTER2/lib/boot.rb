# frozen_string_literal: true

require "time"

module MASTER
  module Boot
    class << self
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")
        user = ENV["USER"] || "user"
        host = `hostname`.strip rescue "localhost"

        puts c("MASTER #{VERSION} (PIPELINE) #1: #{timestamp}")
        puts c("    #{user}@#{host}:#{MASTER.root}")
        puts c("cpu0 at mainbus0: #{RUBY_PLATFORM}, ruby #{RUBY_VERSION}")
        puts c("db0 at cpu0: #{DB.axioms.size} axioms, #{DB.council.size} personas")
        puts c("llm0 at db0: openrouter, #{tier_summary}")
        puts c("budget0 at llm0: #{UI.currency(LLM.budget_remaining)} remaining")
        puts c("pledge0 at cpu0: #{Pledge.available? ? 'armed' : 'unavailable'}")
        puts c("pipeline0 at pledge0: #{Pipeline::DEFAULT_STAGES.size} stages")
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts c("boot: #{elapsed}ms")
        puts
      end

      private

      def c(text)
        UI.colorize(text)
      end

      def tier_summary
        LLM.model_tiers.keys.join("/")
      end
    end
  end
end
