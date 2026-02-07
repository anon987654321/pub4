# frozen_string_literal: true

require "time"

module MASTER
  # Boot - OpenBSD dmesg-style startup (dense, terse, beautiful)
  module Boot
    class << self
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")
        user = ENV["USER"] || ENV["USERNAME"] || "user"
        host = `hostname`.strip rescue "localhost"

        # Dense dmesg - no fluff, no breathing room
        puts c("MASTER #{VERSION} #1: #{timestamp}")
        puts c("#{user}@#{host}:#{MASTER.root}")
        puts c("cpu0 at mainbus0: #{RUBY_PLATFORM}")
        puts c("ruby0 at cpu0: ruby #{RUBY_VERSION}")
        puts c("db0 at ruby0: #{DB.axioms.size} axioms, #{DB.council.size} personas")
        puts c("llm0 at db0: openrouter #{tier_models}")
        puts c("budget0 at llm0: #{UI.currency(LLM.budget_remaining)} remaining")
        puts c("tts0 at budget0: #{tts_status}")
        puts c("self0 at tts0: #{self_awareness_summary}")
        puts c("pledge0 at cpu0: #{Pledge.available? ? 'armed' : 'unavailable'}")
        puts c("pipeline0 at pledge0: #{Pipeline::DEFAULT_STAGES.join(' → ')}")
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts c("boot: #{elapsed}ms")
        puts
      end

      # For web mode, also print the URL
      def banner_with_web(port)
        banner
        puts c("web0 at pipeline0: http://localhost:#{port}")
        puts
      end

      private

      def c(text)
        UI.colorize(text)
      end

      def tier_models
        LLM.model_tiers.map do |tier, models|
          names = models.first(2).map { |m| LLM.extract_model_name(m) }.join(",")
          "#{tier}:#{names}"
        end.join(" ")
      end

      def tts_status
        Audio.engine_status
      rescue StandardError
        "off"
      end

      def self_awareness_summary
        SelfAwareness.summary
      rescue StandardError
        "unavailable"
      end
    end
  end
end
