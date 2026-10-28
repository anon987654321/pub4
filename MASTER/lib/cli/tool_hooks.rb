# frozen_string_literal: true

require "json"
require "yaml"
require "rbconfig"

module Master
  module CLI
    # User-defined PreToolUse hooks for the Fold. A hook is a program the person
    # owns that sees an effect before it runs and may refuse it.
    #
    #   PreToolUse:
    #     - matcher: Bash|Write        # regexp over the tool name; absent matches all
    #       command: [ruby, /home/me/guard.rb]   # argv, never a shell string
    #       on_fault: deny             # optional; a crash, timeout or missing program refuses
    #
    # The program reads one JSON object on stdin (hook_event_name, tool_name,
    # tool_input) and answers with its exit status: 0 allows, 2 refuses with
    # stderr as the reason, anything else is a hook fault. Faults deny by default;
    # an explicit on_fault: allow is the only opt-in to fail-open behavior. The
    # Fold's verbs map to the names a hook author already knows: exec is Bash,
    # write is Write.
    #
    # The file is read from the person's home, never from the workspace: the
    # Fold writes into the workspace, and a hook it could author would run
    # outside the Constitution on the next turn. The file and parent directory
    # must be owned by the current user or root and not writable by group/others;
    # an invalid configured file refuses effects rather than disabling hooks.
    # A hook can only add refusals; it never widens what the Constitution allows.
    module ToolHooks
      module_function

      TIMEOUT_S = 10
      EVENT = "PreToolUse"
      CONFIG_REFUSAL = [[nil, [].freeze, true].freeze].freeze

      def path
        ENV.fetch("MASTER_HOOKS") { File.join(Dir.home, ".master", "hooks.yml") }
      end

      # A hook is a command run with the person's authority, so its file is
      # trusted only when no one else can have written it.
      def trusted?(file)
        stat = File.lstat(file)
        parent = File.lstat(File.dirname(file))
        trusted_owner = [Process.euid, 0]
        stat.file? && !stat.symlink? && stat.nlink == 1 && trusted_owner.include?(stat.uid) &&
          (stat.mode & 0o022).zero? && parent.directory? && !parent.symlink? &&
          trusted_owner.include?(parent.uid) && (parent.mode & 0o022).zero?
      rescue SystemCallError
        false
      end

      # Entries are [Regexp|nil, argv, closed]. An absent file means no hooks.
      # A present but untrusted or malformed file installs a deny-all sentinel;
      # misconfiguration can never silently disable a configured security gate.
      def entries(file = path)
        return [] unless File.exist?(file) || File.symlink?(file)

        unless trusted?(file)
          Master::Trace::Dmesg.status("hook0", "hooks invalid, untrusted path or permissions; effects will be refused", io: $stderr)
          return CONFIG_REFUSAL
        end

        config = YAML.safe_load_file(file, aliases: false)
        raise TypeError, "hooks.yml root must be a mapping" unless config.is_a?(Hash)
        source_rows = config[EVENT]
        return [] if source_rows.nil?
        raise TypeError, "#{EVENT} must be a sequence" unless source_rows.is_a?(Array)

        source_rows.map do |row|
          raise TypeError, "each hook must be a mapping" unless row.is_a?(Hash)
          command = row["command"]
          unless command.is_a?(Array) && !command.empty? && command.all? { |arg| arg.is_a?(String) && !arg.empty? }
            raise TypeError, "hook command must be a non-empty argv array of strings"
          end

          matcher = row["matcher"].to_s
          pattern = matcher.empty? || matcher == "*" ? nil : Regexp.new("\\A(?:#{matcher})\\z")
          # Deny on crash/timeout/missing executable by default. Only an explicit
          # on_fault: allow may preserve the older fail-open behavior.
          closed = row["on_fault"].to_s != "allow"
          [pattern, command, closed]
        end
      rescue Psych::Exception, SystemCallError, TypeError, RegexpError => e
        Master::Trace::Dmesg.status("hook0", "hooks invalid, #{e.class}: #{e.message}; effects will be refused", io: $stderr)
        CONFIG_REFUSAL
      end

      # The first refusal, as a reason string, or nil. Every matching hook runs
      # until one refuses.
      def refusal(tool_name, tool_input, root:, hooks: entries)
        payload = JSON.generate(hook_event_name: EVENT, tool_name:, tool_input:)
        hooks.each do |matcher, argv, closed|
          next if matcher && !matcher.match?(tool_name)
          return "hook configuration invalid or untrusted; refusing #{tool_name}" if argv.empty? && closed

          reason = ask(argv, payload, root:, closed:)
          return reason if reason
        end
        nil
      end

      def ask(argv, payload, root:, closed: false)
        _out, err, status = Master::Io::Exec.capture3(*argv, stdin_data: payload, chdir: root, timeout: TIMEOUT_S)
        return nil if status.success?
        return "hook refused #{argv.first}: #{err.to_s.strip}".strip.chomp(":") if status.exitstatus == 2

        fault(argv, "exit #{status.exitstatus.inspect}", closed)
      rescue StandardError => e
        fault(argv, "#{e.class}: #{e.message}", closed)
      end

      def fault(argv, detail, closed)
        action = closed ? "refusing" : "allowing by explicit on_fault: allow"
        Master::Trace::Dmesg.status("hook0", "#{argv.first} faulted, #{detail}; #{action}", io: $stderr)
        closed ? "hook faulted #{argv.first}: #{detail} (on_fault: deny)" : nil
      end

      # Wrap the exec sandbox the Constitution already holds. A hook refusal is a
      # deny string; the base answer, ask included, passes through unchanged.
      def wrap_sandbox(base, root:, hooks: entries)
        return base if hooks.empty?

        lambda do |argv|
          refusal("Bash", { command: argv.join(" "), argv: }, root:, hooks:) || base&.call(argv)
        end
      end

      # Wrap the write verifier: a refusal joins the blocking findings.
      def wrap_verifier(base, root:, hooks: entries)
        return base if hooks.empty?

        lambda do |path:, content:|
          blocking = base ? base.call(path:, content:) : []
          reason = refusal("Write", { file_path: path.to_s, content: }, root:, hooks:)
          reason ? [*blocking, reason] : blocking
        end
      end
    end
  end
end
