# frozen_string_literal: true

module Master
  module Runtime
    module Jit
      MODES = %w[auto off yjit zjit].freeze

      module_function

      def mode
        configured = ENV.fetch("MASTER_JIT", "auto").to_s.strip.downcase
        return configured if MODES.include?(configured)

        Master::Trace::Dmesg.status("jit0", "unknown configuration #{configured.inspect}, using auto")
        "auto"
      end

      def yjit_available?
        defined?(RubyVM::YJIT) &&
          RubyVM::YJIT.respond_to?(:enable) &&
          RubyVM::YJIT.respond_to?(:runtime_stats)
      end

      def zjit_available?
        defined?(RubyVM::ZJIT) &&
          RubyVM::ZJIT.respond_to?(:enable) &&
          RubyVM::ZJIT.respond_to?(:enabled?)
      end

      def available?(backend = :yjit)
        backend.to_sym == :zjit ? zjit_available? : yjit_available?
      end

      def yjit_enabled?
        yjit_available? && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled?
      end

      def zjit_enabled?
        zjit_available? && RubyVM::ZJIT.enabled?
      rescue StandardError
        false
      end

      def enabled?(backend = :yjit)
        backend.to_sym == :zjit ? zjit_enabled? : yjit_enabled?
      end

      def constrained?
        Master::Ground::HostBudget.constrained?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.constrained?")
        false
      end

      def auto_allowed?
        yjit_available? && !constrained? && !RUBY_PLATFORM.include?("android")
      end

      def apply!
        case mode
        when "off"
          false
        when "zjit"
          enable_zjit!(reason: "forced")
        when "yjit"
          enable_yjit!(reason: "forced")
        else
          return false unless auto_allowed?

          enable_yjit!(reason: "auto")
        end
      end

      def enable!(reason: "manual", backend: :yjit)
        backend.to_sym == :zjit ? enable_zjit!(reason:) : enable_yjit!(reason:)
      end

      def enable_yjit!(reason: "manual")
        return true if yjit_enabled?
        return false unless yjit_available?

        RubyVM::YJIT.enable
        Master::Trace::Dmesg.status("jit0", "yjit enabled, #{reason}")
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.enable_yjit!")
        Master::Trace::Dmesg.status("jit0", "yjit unavailable, #{e.class}: #{e.message}")
        false
      end

      def enable_zjit!(reason: "manual")
        return true if zjit_enabled?
        return false unless zjit_available?

        result = RubyVM::ZJIT.enable
        enabled = zjit_enabled?
        state = enabled ? "enabled" : "not enabled"
        Master::Trace::Dmesg.status("jit0", "zjit #{state}, #{reason}")
        enabled || result == true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.enable_zjit!")
        Master::Trace::Dmesg.status("jit0", "zjit unavailable, #{e.class}: #{e.message}")
        false
      end

      def stats
        if yjit_enabled? || (mode != "zjit" && yjit_available?)
          return RubyVM::YJIT.runtime_stats || {}
        end
        return {} unless zjit_available? && RubyVM::ZJIT.respond_to?(:stats)
        return {} unless RubyVM::ZJIT.respond_to?(:stats_enabled?) ? RubyVM::ZJIT.stats_enabled? : true

        RubyVM::ZJIT.stats || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.stats")
        {}
      end

      def snapshot
        {
          mode:,
          available: available?(mode == "zjit" ? :zjit : :yjit),
          enabled: enabled?(mode == "zjit" ? :zjit : :yjit),
          constrained: constrained?,
          yjit_available: yjit_available?,
          yjit_enabled: yjit_enabled?,
          zjit_available: zjit_available?,
          zjit_enabled: zjit_enabled?,
          stats:,
        }.freeze
      end
    end
  end
end
