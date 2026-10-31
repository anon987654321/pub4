# frozen_string_literal: true

require "tty-prompt"

module Master
  module Fix
    class Governor
      RATE_WINDOW = 60.0
      TIERS = { safe: 0, guarded: 1, dangerous: 2 }.freeze

      # Settings under budgets.yml's `governor:` key: rate_limits, and the @auto gates below, added when the
      # unattended dangerous-tier hole was closed.
      def self.governor_settings
        Master.config_section("governor") || {}
      end

      # Sliding-window rate limits per tier (calls per minute), from budgets.yml governor.rate_limits. They guard
      # against a runaway loop, not against work: three shell calls a minute made an analysis impossible.
      def self.rate_limits
        governor_settings["rate_limits"] || {}
      end

      # Exact tool names an unattended run may use on the dangerous tier without spending the per-run budget.
      # Persistent, operator-owned, and never widened by anything that runs inside a session.
      def self.auto_allowlist
        Array(governor_settings["auto_allowlist"]).map(&:to_s)
      end

      # How many dangerous-tier approvals one unattended run may spend on tools outside the allowlist.
      def self.auto_dangerous_budget
        Integer(governor_settings["auto_dangerous_budget"] || 0)
      end

      def initialize(config:, event_bus: nil)
        @config = config
        @bus = event_bus
        @prompt = $stdout.isatty ? TTY::Prompt.new : nil
        @auto = config.auto?
        @auto_dangerous_budget = self.class.auto_dangerous_budget
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
        when :guarded then return granted if @auto || Fiber[:master_protocol_read]
        when :dangerous
          if @auto
            return Result.ok(true) if !consent_required && !needs_human?(description) &&
                                     auto_dangerous_approved?(tool_name)
          else
            return Result.ok(true) unless needs_human?(description) || consent_required
          end
        end

        ask_user(tool_name:, tier:, description:, one_time: consent_required)
      rescue StandardError => e
        Result.err(e.message, category: :validation)
      end

      alias permit? check_permit

      # @auto used to return ok for the whole dangerous tier before needs_human? was
      # consulted — lib/ground/policy/sandbox.rb:24-33 names that hole, and unattended
      # is exactly when it matters. Two gates now stand between an unattended run and
      # a dangerous tool, and neither widens with use: the persistent allowlist of
      # exact tool names, and a per-run budget for everything else that is spent once
      # and never refilled. When the budget is gone the call falls to ask_user, which
      # fails closed on a non-TTY, so an exhausted budget is a visible refusal the
      # fold observes, not a silent widening. An escalation-shaped description
      # (doas/sudo/su) rides neither gate, and a remembered "always allow" decision
      # still outranks both: it was given by a human, for one exact request.
      def auto_dangerous_approved?(tool_name)
        return true if self.class.auto_allowlist.include?(tool_name.to_s)

        return false unless @auto_dangerous_budget.positive?

        @auto_dangerous_budget -= 1
        @bus&.publish("tool:auto_dangerous", tool: tool_name, budget_left: @auto_dangerous_budget)
        true
      end

      # Decisions are exact to the tool and request description. "Always" never
      # becomes a blanket approval for the whole tier, which keeps an interactive
      # session frictionless without silently widening what the operator approved.
      def allow!(tool_name, description = nil) = @decisions[decision_key(tool_name, description)] = :allow
      def deny!(tool_name, description = nil) = @decisions[decision_key(tool_name, description)] = :deny
      def clear_decisions! = @decisions.clear

      private

      # A protocol read is one Agent#research_sources makes from data-declared sources.
      def granted = Result.ok(true)

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
        tool_name.to_s == "browser" && description.to_s.start_with?("interact ")
      end

      def check_rate_limit!(tier)
        limit = self.class.rate_limits[tier.to_s]
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
          return Result.err("remembered approval is forbidden for this action", category: :validation) if one_time

          allow!(tool_name, description)
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
