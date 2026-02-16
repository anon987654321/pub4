# frozen_string_literal: true

module MASTER
  class AgentFirewall
    # Policy -- tiered autonomy profiles
    # Stolen from OpenClaw: minimal/coding/full profiles with group-based tool access
    module Policy
      TOOL_GROUPS = {
        read: %i[scan stats health version help],
        analyze: %i[scan introspect selftest],
        refactor: %i[fix evolve refactor],
        execute: %i[shell exec run],
        admin: %i[schedule config reset],
      }.freeze

      PROFILES = {
        readonly: { allow: [:read], deny_all_else: true },
        analyze: { allow: %i[read analyze], deny_all_else: true },
        refactor: { allow: %i[read analyze refactor], deny_all_else: true },
        full: { allow: TOOL_GROUPS.keys, deny_all_else: false },
      }.freeze

      class << self
        def current
          @current ||= :refactor
        end

        def set(profile)
          unless PROFILES.key?(profile)
            return Result.err("Unknown profile: #{profile}. Valid: #{PROFILES.keys.join(', ')}.")
          end

          @current = profile
          Logging.dmesg_log("policy", message: "profile=#{profile}")
          Result.ok(profile: profile)
        end

        def allowed?(command)
          profile = PROFILES[current]
          allowed_groups = profile[:allow]
          allowed_commands = allowed_groups.flat_map { |g| TOOL_GROUPS[g] || [] }

          cmd_sym = command.to_s.split.first&.to_sym
          return true unless profile[:deny_all_else]

          allowed_commands.include?(cmd_sym)
        end

        def check!(command)
          return if allowed?(command)

          raise "Blocked by policy '#{current}': #{command}"
        end
      end
    end
  end
end
