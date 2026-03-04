# frozen_string_literal: true

# Permissions — Tiered privilege escalation for tool calls.
# Implements gist item #4: Codex CLI sandbox permission levels.
#
# Tiers (set via MASTER_PERMISSION_TIER env var, default: :refactor):
#   :readonly  — read-only; no writes, no shell, no network
#   :analyze   — read + safe shell (ruby -c, git status); no writes, no network
#   :refactor  — read + workspace writes + safe shell; no network (DEFAULT)
#   :full      — all operations permitted (requires explicit opt-in)
#
# Usage:
#   Permissions.check!(:file_write, path: "lib/foo.rb")   # raises on violation
#   Permissions.permitted?(:shell_command, command: "rm")  # => false

module MASTER
  module Security
    module Permissions
      TIERS = {
        readonly: {
          description: "Read-only: no writes, no shell, no network",
          file_read:     true,
          file_write:    false,
          shell_command: false,
          network:       false,
        },
        analyze: {
          description: "Analyze: read + safe shell only",
          file_read:     true,
          file_write:    false,
          shell_command: :safe,   # only allow-listed commands
          network:       false,
        },
        refactor: {
          description: "Refactor: read + workspace writes + safe shell (default)",
          file_read:     true,
          file_write:    :workspace,  # workspace paths only
          shell_command: :safe,
          network:       false,
        },
        full: {
          description: "Full: all operations (danger — set MASTER_PERMISSION_TIER=full explicitly)",
          file_read:     true,
          file_write:    true,
          shell_command: true,
          network:       true,
        },
      }.freeze

      # Safe shell commands allowed in :analyze and :refactor tiers
      SAFE_SHELL_PREFIXES = %w[
        ruby\ -c ruby\ -e bundle\ exec
        zsh git\ status git\ log git\ diff git\ show git\ branch git\ checkout git\ switch git\ restore git\ add git\ commit git\ fetch git\ pull git\ push git\ clone
        gh\ auth gh\ repo gh\ pr gh\ issue gh\ workflow
        cat\ lib head\ lib grep find\ . ls wc\ -l rubocop
      ].freeze

      module_function

      def current_tier
        key = ENV.fetch("MASTER_PERMISSION_TIER", "refactor").to_sym
        TIERS.key?(key) ? key : :refactor
      end

      # Returns true if the action is permitted in the current (or given) tier.
      def permitted?(action, tier: current_tier, **opts)
        perm = TIERS.dig(tier, action)
        case perm
        when true  then true
        when false then false
        when :safe
          cmd = opts[:command].to_s
          SAFE_SHELL_PREFIXES.any? { |prefix| cmd.start_with?(prefix) }
        when :workspace
          path = File.expand_path(opts[:path].to_s)
          root = File.expand_path(MASTER.root)
          path.start_with?(root)
        else
          false
        end
      end

      # Like permitted? but raises Result::Error (non-exception) on denial.
      def check!(action, tier: current_tier, **opts)
        return Result.ok if permitted?(action, tier: tier, **opts)

        reason = case TIERS.dig(tier, action)
                 when false    then "#{action} not permitted in #{tier} tier"
                 when :safe    then "shell command not in safe-list for #{tier} tier"
                 when :workspace then "path #{opts[:path]} is outside workspace"
                 else "#{action} denied (tier=#{tier})"
                 end

        Logging.dmesg_log("permissions0", message: "DENIED action=#{action} tier=#{tier}") if defined?(Logging)
        Result.err(reason, category: :permissions)
      end
    end
  end
end
