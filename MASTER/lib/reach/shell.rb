# frozen_string_literal: true

require "tty-command"
require "timeout"
require "shellwords"

module Master
  module Reach
    # Shell — execute zsh commands with timeout and governor approval.
    # Three-layer defense (OpenCrabs pattern):
    #   1. BLOCKLIST: hard-blocked destructive commands
    #   2. Interactive detection: block commands that need a TTY
    #   3. Recent failure window: warn after 3 failures in last 5 commands
    class Shell
      TIER = :dangerous
      NAME = "zsh".freeze
      DESCRIPTION = "Execute a zsh command in the project root.".freeze
      TIMEOUT = 30
      FAILURE_WINDOW = 5
      FAILURE_WARN_AT = 3
      FORCE_REQUIRED_RE = /\b(?:rm\s+-rf|dd\s+if=|mkfs(?:\.\w+)?)\b/.freeze
      FORCE_FLAG_RE = /(?:\A|\s)--force(?:\s|\z)/.freeze
      REDIRECT_RE = /(?:^|\s)(?:>|>>)\s*([^\s;&|]+)/.freeze
      PRIVILEGE_RE = /\bdoas\b/.freeze

      BLOCKLIST   = Judge::Security::Permissions::BLOCKLIST
      ZSH_BANNED  = begin
        merged = Master.load_yaml(Master.data_path("patterns.yml"))
        zsh_data = (merged && merged["zsh"]) ||
                    Master.load_yaml(Master.data_path("zsh_patterns.yml"))
        Array(zsh_data["banned_commands"]).freeze
      rescue StandardError => _e
        %w[sed awk grep find head tail wc cut tr bash sudo perl python].freeze
      end

      INTERACTIVE_RE = /\b(
        vim?|nano|less|more|pager|git\s+add\s+-[ip]|
        irb|pry|rails\s+c|bundle\s+exec\s+rails\s+c|fzf|top|htop|tmux|screen
      )\b/ix.freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
        @cmd      = TTY::Command.new(printer: :null)
        @recent   = []
        @mutex    = Mutex.new
      end

      def call(command:)
        return Result.err("blocked command: #{command}", category: :validation) if blocked?(command)
        return Result.err("blocked destructive command without --force: #{command}", category: :validation) if force_required_without_flag?(command)
        return Result.err("write target not writable: #{unwritable_target(command)}", category: :validation) if unwritable_target(command)
        return Result.err("interactive command blocked — no TTY available: #{command}",
                          category: :validation) if interactive?(command)

        warn_if_failing_often

        perm = @governor.permit?(NAME, TIER, command)
        return perm if perm.err?

        @bus&.publish("zsh:privilege_escalation_warning", command:) if command.match?(PRIVILEGE_RE)
        @bus&.publish("tool:before", tool: NAME, command:)

        banned = ZSH_BANNED.select { |b| command.match?(/\b#{Regexp.escape(b)}\b/) }
        @bus&.publish("zsh:banned_tool_warning", tools: banned, command:) if banned.any?

        zdotdir = File.writable?("/tmp") ? "/tmp" : Dir.home
        executable_command = strip_force_sentinel(command)
        wrapped = "#!/usr/bin/env zsh\nset -euo pipefail\nsetopt nullglob extendedglob\n" \
                  "export ZDOTDIR=#{Shellwords.escape(zdotdir)}\nexport LC_ALL=C.UTF-8\n" \
                  "cd #{Shellwords.escape(@root)}\n#{executable_command}\n"

        out, err = Timeout.timeout(TIMEOUT) { @cmd.run!("zsh", input: wrapped) }
        @bus&.publish("tool:after", tool: NAME, exit_code: out.exit_status)

        track_result(:success)
        Result.ok(out.to_s.strip)
      rescue Timeout::Error => _e
        track_result(:failure)
        Result.err("zsh: timed out after #{TIMEOUT}s", category: :unknown)
      rescue TTY::Command::ExitError => e
        track_result(:failure)
        Result.err("zsh: #{e.message}", category: :unknown)
      rescue StandardError => e
        track_result(:failure)
        Result.err("zsh: #{e.message}", category: :unknown)
      end

      private

      def blocked?(command) = BLOCKLIST.any? { |b| command.include?(b) }
      def interactive?(command) = INTERACTIVE_RE.match?(command)

      def force_required_without_flag?(command)
        command.match?(FORCE_REQUIRED_RE) && !command.match?(FORCE_FLAG_RE)
      end

      def strip_force_sentinel(command)
        command.match?(FORCE_REQUIRED_RE) ? command.gsub(FORCE_FLAG_RE, " ") : command
      end

      def unwritable_target(command)
        match = command.match(REDIRECT_RE)
        return nil unless match

        path = File.expand_path(match[1].delete_prefix("./"), @root)
        dir = File.directory?(path) ? path : File.dirname(path)
        File.writable?(dir) ? nil : path
      end

      def track_result(outcome)
        @mutex.synchronize do
          @recent << outcome
          @recent = @recent.last(FAILURE_WINDOW)
        end
      end

      def warn_if_failing_often
        failures = @mutex.synchronize { @recent.count(:failure) }
        @bus&.publish("zsh:high_failure_rate", failures:, window: FAILURE_WINDOW) if failures >= FAILURE_WARN_AT
      end
    end
  end
end
