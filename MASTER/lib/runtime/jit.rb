# frozen_string_literal: true

module Master
  module Runtime
    module Jit
      MODES = %w[auto off yjit].freeze

      module_function

      def mode
        configured = ENV.fetch("MASTER_JIT", "auto").to_s.strip.downcase
        return configured if MODES.include?(configured)

        warn("jit0: unknown MASTER_JIT=#{configured.inspect} — using auto")
        "auto"
      end

      def available?
        defined?(RubyVM::YJIT) &&
          RubyVM::YJIT.respond_to?(:enable) &&
          RubyVM::YJIT.respond_to?(:runtime_stats)
      end

      def enabled?
        available? && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled?
      end

      def constrained?
        Master::Ground::HostBudget.constrained?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.constrained?")
        false
      end

      def auto_allowed?
        available? && !constrained? && !RUBY_PLATFORM.include?("android")
      end

      def apply!
        case mode
        when "off"
          false
        when "yjit"
          enable!(reason: "forced")
        else
          return false unless auto_allowed?

          enable!(reason: "auto")
        end
      end

      def enable!(reason: "manual")
        return true if enabled?
        return false unless available?

        RubyVM::YJIT.enable
        warn("jit0: yjit enabled (#{reason})")
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.enable!")
        warn("jit0: yjit unavailable — #{e.class}: #{e.message}")
        false
      end

      def stats
        return {} unless available?

        RubyVM::YJIT.runtime_stats || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.stats")
        {}
      end

      def snapshot
        { mode:, available: available?, enabled: enabled?, constrained: constrained?, stats: stats }.freeze
      end
    end
  end
end
