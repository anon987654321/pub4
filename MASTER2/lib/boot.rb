# frozen_string_literal: true

require "time"

module MASTER
  module Boot
    class << self
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")

        puts "MASTER #{VERSION} #1: #{timestamp}"
        puts "cpu0: #{RUBY_PLATFORM}, ruby #{RUBY_VERSION}"
        puts "db0: #{DB.axioms.size} axioms, #{DB.council.size} personas"
        puts "llm0: openrouter, #{tier_summary}, #{UI.currency(LLM.budget_remaining)}"
        puts "pledge0: #{Pledge.available? ? 'armed' : 'unavailable'}"
        puts "pipeline0: #{Pipeline::DEFAULT_STAGES.size} stages"
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts "boot: #{elapsed}ms"
        puts
      end

      private

      def tier_summary
        LLM.model_tiers.keys.join("/")
      end
    end
  end
end
