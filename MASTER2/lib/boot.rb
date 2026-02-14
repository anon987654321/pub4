# frozen_string_literal: true

require "time"

module MASTER
  # Boot - OpenBSD dmesg-style startup (dense, terse, beautiful)
  module Boot
    class << self
      # Lazy SMOKE_TEST_METHODS to avoid crashes if modules didn't load
      def smoke_test_methods
        {
          LLM => %i[ask pick tier=],
          Executor => %i[call],
          Result => %i[ok err ok? err?],
        }
      rescue NameError => e
        warn "Smoke test skipped: #{e.message}"
        {}
      end
      def banner
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")
        user = ENV["USER"] || ENV["USERNAME"] || "user"
        host = `hostname`.strip rescue "localhost"

        # Smoke test first - catch runtime errors early
        smoke_result = smoke_test

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
        puts c("executor0 at pledge0: #{Executor::PATTERNS.join('/')}")
        puts c("smoke0 at executor0: #{smoke_result}")
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        puts c("boot: #{elapsed}ms")
        puts
      end

      # For web mode, also print the URL
      def banner_with_web(port)
        banner
        puts c("web0 at smoke0: http://localhost:#{port}")
        puts
      end

      # Verify critical methods exist at runtime
      def smoke_test
        missing = []
        
        smoke_test_methods.each do |mod, methods|
          methods.each do |method|
            unless mod.respond_to?(method) || (mod.is_a?(Class) && mod.instance_methods.include?(method))
              missing << "#{mod}##{method}"
            end
          end
        end
        
        # Also check optional modules
        optional_checks = []
        optional_checks << "Chamber" if defined?(Chamber) && !Chamber.respond_to?(:council_review)
        optional_checks << "CodeReview" if defined?(CodeReview) && !CodeReview.respond_to?(:analyze)
        optional_checks << "AutoFixer" if defined?(AutoFixer) && !AutoFixer.new.respond_to?(:fix)
        
        if missing.any?
          UI.warn("Missing methods: #{missing.join(', ')}")
          "FAIL #{missing.size}"
        elsif optional_checks.any?
          "WARN #{optional_checks.join(',')}"
        else
          "ok"
        end
      rescue StandardError => e
        "FAIL #{e.message[0..30]}"
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
        Speech.engine_status
      rescue StandardError
        "off"
      end

      def self_awareness_summary
        SelfMap.summary
      rescue StandardError
        "unavailable"
      end
    end
  end
end
