# frozen_string_literal: true

require "tty-command"
require "timeout"
require "shellwords"

module Master
  module Io
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

      BLOCKLIST   = Review::Security::Permissions::BLOCKLIST
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

      BINARY_RE = /\b(?:bundle|ruby|rake|git|node|npm|yarn|python\d*|perl)\b/.freeze

      def initialize(root:, governor:, event_bus: nil, library_verify: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
        @library_verify = library_verify || Ground::LibraryVerify.new(root:)
        @cmd      = TTY::Command.new(printer: :null)
        @recent   = []
        @mutex    = Mutex.new
      end

      def call(command:)
        warn_privilege_escalation(command)
        error = preflight_error(command)
        return error if error

        warn_if_failing_often
        perm = @governor.permit?(NAME, TIER, command)
        return perm if perm.err?

        capture_output(command)
      rescue Timeout::Error
        failed_result("timed out after #{TIMEOUT}s")
      rescue TTY::Command::ExitError => e
        failed_result(e.message)
      rescue StandardError => e
        failed_result(e.message)
      end

      private

      def preflight_error(command)
        verify_binaries(command) || blocked_error(command) || force_error(command) ||
          batch_delete_error(command) || writable_error(command) || interactive_error(command)
      end

      def batch_delete_error(command)
        argv = Shellwords.split(command.to_s)
        reason = Master::Core::Constitution.batch_delete_reason(argv)
        Result.err(reason, category: :validation) if reason
      rescue ArgumentError
        nil
      end

      def blocked_error(command)
        Result.err("blocked command: #{command}", category: :validation) if blocked?(command)
      end

      def force_error(command)
        return unless force_required_without_flag?(command)

        Result.err("blocked destructive command without --force: #{command}", category: :validation)
      end

      def writable_error(command)
        target = unwritable_target(command)
        Result.err("write target not writable: #{target}", category: :validation) if target
      end

      def interactive_error(command)
        return unless interactive?(command)

        Result.err("interactive command blocked — no TTY available: #{command}", category: :validation)
      end

      def capture_output(command)
        executable = strip_force_sentinel(command)
        publish_before(command)
        output, = Timeout.timeout(TIMEOUT) { @cmd.run!("zsh", input: wrapped_command(executable)) }
        @bus&.publish("tool:after", tool: NAME, exit_code: output.exit_status)
        successful_result(executable, output.to_s.strip)
      end

      def wrapped_command(command)
        dot_directory = File.writable?("/tmp") ? "/tmp" : Dir.home
        "#!/usr/bin/env zsh\nset -euo pipefail\nsetopt nullglob extendedglob\n" \
          "export ZDOTDIR=#{Shellwords.escape(dot_directory)}\nexport LC_ALL=C.UTF-8\n" \
          "cd #{Shellwords.escape(@root)}\n#{command}\n"
      end

      def publish_before(command)
        @bus&.publish("tool:before", tool: NAME, command:)
        banned = ZSH_BANNED.select { |binary| command.match?(/\b#{Regexp.escape(binary)}\b/) }
        @bus&.publish("zsh:banned_tool_warning", tools: banned, command:) if banned.any?
      end

      def successful_result(command, raw)
        track_result(:success)
        filtered = OutputFilter.filter(command:, output: raw)
        @bus&.publish("rtk:filtered", saved_bytes: raw.bytesize - filtered.bytesize) if filtered != raw
        Result.ok(filtered)
      end

      def failed_result(message)
        track_result(:failure)
        Result.err("zsh: #{message}", category: :unknown)
      end

      def verify_binaries(command)
        command.to_s.scan(BINARY_RE).uniq.each do |binary|
          result = @library_verify.verify_binary!(binary)
          return result if result.err?
        end
        nil
      end

      def blocked?(command)
        BLOCKLIST.any? { |b| command.include?(b) }
      end

      def interactive?(command)
        INTERACTIVE_RE.match?(command)
      end

      def force_required_without_flag?(command)
        command.match?(FORCE_REQUIRED_RE) && !command.match?(FORCE_FLAG_RE)
      end

      def strip_force_sentinel(command)
        command.match?(FORCE_REQUIRED_RE) ? command.gsub(FORCE_FLAG_RE, " ") : command
      end

      def unwritable_target(command)
        match = command.match(REDIRECT_RE)
        return unless match

        path = File.expand_path(match[1].delete_prefix("./"), @root)
        dir = File.directory?(path) ? path : File.dirname(path)
        File.writable?(dir) ? nil : path
      end

      def warn_privilege_escalation(command)
        return unless command.match?(PRIVILEGE_RE)

        @bus&.publish("voice:catchphrase", phrase: "That looks risky. Confirm?", command:)
        @bus&.publish("zsh:privilege_escalation_warning", command:)
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
