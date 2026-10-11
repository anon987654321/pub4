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
        @decisions = {}
        @rate_windows = Hash.new { |h, k| h[k] = [] }
        @rate_mutex = Mutex.new
      end

      def check_permit(tool_name, tier, description = nil)
        @bus&.publish("tool:before", tool: tool_name, tier:)

        if (rate_err = check_rate_limit!(tier))
          @bus&.publish("tool:rate_limited", tool: tool_name, tier:)
          return rate_err
        end

        consent_required = human_consent_required?(tool_name, description)
        decision = @decisions[decision_key(tool_name, description)]
        return Result.err("denied by policy", category: :validation) if decision == :deny
        return Result.ok(true) if decision == :allow && !consent_required

        case tier
        when :safe then return Result.ok(true)
        when :guarded then return Result.ok(true) if @auto
        when :dangerous
          return Result.ok(true) if @auto && !consent_required
          return Result.ok(true) unless needs_human?(description) || consent_required
        end

        ask_user(tool_name:, tier:, description:, one_time: consent_required)
      rescue StandardError => e
        Result.err(e.message, category: :validation)
      end

      alias permit? check_permit

      # Decisions are exact to the tool and request description. "Always" never
      # becomes a blanket approval for the whole tier, which keeps an interactive
      # session frictionless without silently widening what the operator approved.
      def allow!(tool_name, description = nil) = @decisions[decision_key(tool_name, description)] = :allow
      def deny!(tool_name, description = nil) = @decisions[decision_key(tool_name, description)] = :deny
      def clear_decisions! = @decisions.clear

      private

      def decision_key(tool_name, description)
        [tool_name.to_s, description.to_s]
      end

      PRIVILEGE_RE = /\b(?:doas|sudo|su)\b/.freeze

      def needs_human?(description)
        description.to_s.match?(PRIVILEGE_RE)
      end

      # Browser writes are never approved by unattended mode or a remembered
      # "always allow" choice. Consent covers one concrete interaction only.
      def human_consent_required?(tool_name, description)
        tool_name.to_s == "browser_agent" && description.to_s.start_with?("interact ")
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

      APPROVAL_OPTIONS = [
        { name: "approve once", value: "approve" },
        { name: "always allow this request", value: "allow" },
        { name: "deny this request", value: "deny" },
        { name: "quit", value: "quit" },
      ].freeze

      def ask_user(tool_name:, tier:, description:, one_time: false)
        label = description ? "#{tool_name}: #{description}" : tool_name
        if (asker = Fiber[:master_terminal_ask])
          return ask_via_terminal(asker, tool_name:, tier:, description:, label:, one_time:)
        end
        return Result.err("non-TTY: cannot prompt for approval", category: :validation) unless @prompt
        choices = [
          { name: "approve once", value: :approve },
          { name: "deny this request", value: :deny },
          { name: "quit", value: :quit },
        ]
        choices.insert(1, { name: "always allow this request", value: :allow }) unless one_time
        choice = @prompt.select("#{tier_icon(tier)} #{label}", choices)

        case choice
        when :approve then Result.ok(true)
        when :allow
          allow!(tool_name, description) unless one_time
          Result.ok(true)
        when :deny
          deny!(tool_name, description)
          @bus&.publish("tool:denied", tool: tool_name)
          Result.err("denied by user", category: :validation)
        when :quit then Result.err("quit", category: :shutdown)
        end
      rescue TTY::Reader::InputInterrupt
        @bus&.publish("tool:prompt_interrupted", tool: tool_name, tier:)
        Result.err("input interrupted", category: :shutdown)
      end

      def ask_via_terminal(asker, tool_name:, tier:, description:, label:, one_time: false)
        options = one_time ? APPROVAL_OPTIONS.reject { |option| option[:value] == "allow" } : APPROVAL_OPTIONS
        choice = asker.call(prompt: "#{tier_icon(tier)} #{label}", options:)
        case choice.to_s
        when "approve" then Result.ok(true)
        when "allow"
          return Result.err("remembered approval is forbidden for this action", category: :validation) if one_time

          allow!(tool_name, description)
          Result.ok(true)
        when "deny"
          deny!(tool_name, description)
          @bus&.publish("tool:denied", tool: tool_name)
          Result.err("denied by user", category: :validation)
        when "quit" then Result.err("quit", category: :shutdown)
        else Result.err("invalid approval choice", category: :validation)
        end
      rescue StandardError => e
        @bus&.publish("tool:prompt_error", tool: tool_name, tier:, error: e.message)
        Result.err("approval prompt failed: #{e.class}: #{e.message}", category: :validation)
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
