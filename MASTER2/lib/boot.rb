# frozen_string_literal: true

module MASTER
  module Boot
    OPTIONAL_MODULES = {
      "Council" => :council_review,
      "CodeReview" => :analyze,
      "AutoFixer" => :fix,
    }.freeze

    class << self
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
        start_time = MASTER::Utils.monotonic_now
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")
        user = ENV["USER"] || ENV["USERNAME"] || "user"
        host = begin
          require 'timeout'
          Timeout.timeout(2) { `hostname`.strip }
        rescue Timeout::Error
          "unknown"
        rescue StandardError
          "unknown"
        end

        smoke_result = smoke_test

        lines = [
          c("MASTER #{VERSION} (CONSTITUTIONAL) #1: #{timestamp}"),
          c("    #{user}@#{host}:#{MASTER.root}"),
          c("cpu0 at mainbus0: #{RUBY_PLATFORM}, ruby #{RUBY_VERSION}"),
          c("db0 at cpu0: #{DB.axioms.size} axioms, #{defined?(DB) && DB.respond_to?(:council) ? DB.council.size : 0} personas"),
          c("llm0 at db0: #{tier_models}"),
          c("budget0 at llm0: #{UI.currency(LLM.budget_remaining)}"),
          c("pledge0 at cpu0: #{defined?(Pledge) && Pledge.available? ? 'armed' : 'unavailable'}"),
          c("executor0 at pledge0: #{Executor::PATTERNS.join('/')}"),
          c("smoke0 at executor0: #{smoke_result}"),
        ]

        yield(lines) if block_given?

        elapsed = ((MASTER::Utils.monotonic_now - start_time) * 1000).round
        lines << c("boot: #{elapsed}ms")

        puts lines.join("\n")
        puts
      end

      def banner_with_web(port)
        banner do |lines|
          lines << c("web0 at smoke0: http://localhost:#{port}")
        end
      end

      def smoke_test
        missing = []

        smoke_test_methods.each do |mod, methods|
          methods.each do |method|
            unless mod.respond_to?(method) || (mod.is_a?(Class) && mod.instance_methods.include?(method))
              missing << "#{mod}##{method}"
            end
          end
        end

        optional_checks = OPTIONAL_MODULES.select do |name, method|
          mod = begin
            MASTER.const_get(name)
          rescue NameError => e
            MASTER::Logging.warn("boot", "Failed to resolve constant: #{name} — #{e.message}") if defined?(MASTER::Logging)
            nil
          end
          mod && !mod.respond_to?(method) && !mod.instance_methods.include?(method)
        end.keys

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
        LLM.all_models.map { |m| LLM.extract_model_name(m) }.first(6).join(", ")
      end
    end
  end
end
