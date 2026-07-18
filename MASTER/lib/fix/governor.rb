# frozen_string_literal: true

require "tty-prompt"

module Master
  module Fix
    class Governor
      RATE_WINDOW = 60.0
      TIERS = { safe: 0, guarded: 1, dangerous: 2 }.freeze

      # Sliding-window rate limits per tier (calls per minute).
      TIER_RATE_LIMITS = { guarded: 10, dangerous: 3 }.freeze

      def initialize(config:, event_bus: nil)
        @config = config
        @bus = event_bus
        @prompt = $stdout.isatty ? TTY::Prompt.new : nil
        @auto = config.auto?
        @approve_all = false
        @rate_windows = Hash.new { |h, k| h[k] = [] }
        @rate_mutex = Mutex.new
      end

      def check_permit(tool_name, tier, description = nil)
        @bus&.publish("tool:before", tool: tool_name, tier:)

        if (rate_err = check_rate_limit!(tier))
          @bus&.publish("tool:rate_limited", tool: tool_name, tier:)
          return rate_err
        end

        case tier
        when :safe then return Result.ok(true)
        when :guarded then return Result.ok(true) if @auto || @approve_all
        when :dangerous
          return Result.ok(true) if @auto || @approve_all
          return Result.ok(true) unless needs_human?(description)
        end

        ask_user(tool_name:, tier:, description:)
      rescue StandardError => e
        Result.err(e.message, category: :validation)
      end

      alias permit? check_permit

      def approve_all! = @approve_all = true
      def reset_approve! = @approve_all = false

      private

      PRIVILEGE_RE = /\b(?:doas|sudo|su)\b/.freeze

      def needs_human?(description)
        description.to_s.match?(PRIVILEGE_RE)
      end

      def check_rate_limit!(tier)
        limit = TIER_RATE_LIMITS[tier]
        return unless limit
        now = Time.now.to_f
        @rate_mutex.synchronize do
          calls = @rate_windows[tier]
          calls.reject! { |t| now - t > RATE_WINDOW }
          if calls.size >= limit
            return Result.err("rate limit: #{tier} tier (#{limit}/min)", category: :rate_limit)
          end
          calls << now
        end
        nil
      end

      def ask_user(tool_name:, tier:, description:)
        return Result.err("non-TTY: cannot prompt for approval", category: :validation) unless @prompt

        label = description ? "#{tool_name}: #{description}" : tool_name
        choice = @prompt.select("#{tier_icon(tier)} #{label}", [
          { name: "approve", value: :approve },
          { name: "deny", value: :deny },
          { name: "quit", value: :quit }
        ])

        case choice
        when :approve then Result.ok(true)
        when :deny
          @bus&.publish("tool:denied", tool: tool_name)
          Result.err("denied by user", category: :validation)
        when :quit then Result.err("quit", category: :shutdown)
        end
      end

      def tier_icon(tier)
        case tier
        when :safe then "i"
        when :guarded then "!"
        when :dangerous then "!!"
        end
      end
    end
  end
end
