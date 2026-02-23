# frozen_string_literal: true

module MASTER
  module Boot
    OPTIONAL_MODULES = {
      "Council" => :council_review,
      "CodeReview" => :analyze,
    }.freeze

    class << self
      def smoke_test_methods
        {
          LLM => %i[ask tier=],
          Executor => %i[call],
          Result => %i[ok err ok? err?],
        }
      rescue NameError => err
        warn "Smoke test skipped: #{err.message}"
        {}
      end

      def banner
        start_time = MASTER::Utils.monotonic_now
        timestamp = Time.now.utc.strftime("%a %b %e %H:%M:%S UTC %Y")
        user = ENV["USER"] || ENV["USERNAME"] || "user"
        shell = ENV["SHELL"] ? File.basename(ENV["SHELL"]) : "unknown-shell"
        prompt_hint = shell == "zsh" ? "%" : "$"
        host = begin
          require "timeout"
          Timeout.timeout(2) { `hostname`.strip }
        rescue Timeout::Error, StandardError
          "unknown"
        end

        smoke_result = smoke_test

        lines = [
          c("MASTER #{VERSION} (CONSTITUTIONAL) #1: #{timestamp}"),
          c("    #{user}@#{host}:#{MASTER.root}"),
          c("runtime0: #{RUBY_PLATFORM} * ruby #{RUBY_VERSION} * #{shell} #{user}#{prompt_hint}"),
          c("host0: #{PlatformCheck.hypervisor} * #{PlatformCheck.provider}"),
          c("hw0: #{PlatformCheck.cpu_cores}c * #{PlatformCheck.total_mem_mb || '?'}M RAM * #{PlatformCheck.free_mem_mb || '?'}M free"),
          c("corpus0: #{UI.pluralize(DB.axioms.size, 'axiom')} * #{UI.pluralize(defined?(DB) && DB.respond_to?(:council) ? DB.council.size : 0, 'persona')}"),
          c("models0: #{tier_models}"),
          c("routing0: #{if LLM.configured_for_replicate?
                           "Replicate primary#{LLM.configured_for_openrouter? ? ', OpenRouter fallback' : ''}"
                         else
                           'OpenRouter'
                         end}"),
          c("security0: #{defined?(Pledge) && Pledge.available? ? 'pledge armed' : 'pledge unavailable'}"),
          c("engine0: #{Executor::PATTERNS.join(' * ')}"),
          c("smoke0: #{smoke_result}"),
        ]

        yield(lines) if block_given?

        elapsed = ((MASTER::Utils.monotonic_now - start_time) * 1000).round
        lines << c("boot0: #{elapsed}ms")

        puts lines.join("\n")
        puts
      end

      def banner_with_web(port, token = nil)
        banner do |lines|
          url = token ? "http://localhost:#{port}/?token=#{token}" : "http://localhost:#{port}"
          lines << c("web0: #{url}")
        end
      end

      def smoke_test
        missing = []

        smoke_test_methods.each do |mod, methods|
          methods.each do |method|
            unless mod.respond_to?(method) || (mod.is_a?(Class) && mod.method_defined?(method))
              missing << "#{mod}##{method}"
            end
          end
        end

        optional_checks = OPTIONAL_MODULES.select do |name, method|
          mod = begin
            MASTER.const_get(name)
          rescue NameError => err
            if defined?(MASTER::Logging)
              MASTER::Logging.warn("Failed to resolve constant: #{name} -- #{err.message}", subsystem: "boot")
            end
            nil
          end
          mod && !mod.respond_to?(method) && !mod.method_defined?(method)
        end.keys

        if missing.any?
          UI.warn("Missing methods: #{missing.join(', ')}")
          "FAIL #{missing.size}"
        elsif optional_checks.any?
          "WARN #{optional_checks.join(',')}"
        else
          "ok"
        end
      rescue StandardError => err
        "FAIL #{err.message[0..30]}"
      end

      private

      def c(text)
        UI.colorize(text)
      end

      def tier_models
        tiers = LLM.model_tiers
        %i[strong fast free].filter_map do |t|
          m = tiers[t]&.first
          m && LLM.extract_model_name(m)
        end.join(" * ")
      rescue StandardError
        LLM.all_models.map { |m| LLM.extract_model_name(m) }.uniq.first(3).join(" * ")
      end
    end
  end
end
