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
    #
    # The program reads one JSON object on stdin (hook_event_name, tool_name,
    # tool_input) and answers with its exit status: 0 allows, 2 refuses with
    # stderr as the reason, anything else is a hook fault that allows and is
    # logged. The Fold's verbs map to the names a hook author already knows:
    # exec is Bash, write is Write.
    #
    # The file is read from the person's home, never from the workspace: the
    # Fold writes into the workspace, and a hook it could author would run
    # outside the Constitution on the next turn. A hook can only add refusals;
    # it never widens what the Constitution allows.
    module ToolHooks
      module_function

      TIMEOUT_S = 10
      EVENT = "PreToolUse"

      def path
        ENV.fetch("MASTER_HOOKS") { File.join(Dir.home, ".master", "hooks.yml") }
      end

      # Entries are [Regexp|nil, argv]. A file that is absent holds none; one that
      # does not parse is reported and holds none, since refusing every effect
      # over a typo would stop the Fold for a reason it cannot act on.
      def entries(file = path)
        return [] unless File.file?(file)

        rows = Array(YAML.safe_load_file(file, aliases: false)&.fetch(EVENT, nil))
        rows.filter_map do |row|
          argv = Array(row["command"]).map(&:to_s)
          next if argv.empty?

          matcher = row["matcher"].to_s
          [matcher.empty? || matcher == "*" ? nil : Regexp.new("\\A(?:#{matcher})\\z"), argv]
        end
      rescue Psych::Exception, SystemCallError, TypeError, RegexpError => e
        Master::Trace::Dmesg.status("hook0", "hooks ignored, #{e.class}: #{e.message}", io: $stderr)
        []
      end

      # The first refusal, as a reason string, or nil. Every matching hook runs
      # until one refuses.
      def refusal(tool_name, tool_input, root:, hooks: entries)
        payload = JSON.generate(hook_event_name: EVENT, tool_name:, tool_input:)
        hooks.each do |matcher, argv|
          next if matcher && !matcher.match?(tool_name)

          reason = ask(argv, payload, root:)
          return reason if reason
        end
        nil
      end

      def ask(argv, payload, root:)
        _out, err, status = Master::Io::Exec.capture3(*argv, stdin_data: payload, chdir: root, timeout: TIMEOUT_S)
        return nil if status.success?
        return "hook refused #{argv.first}: #{err.to_s.strip}".strip.chomp(":") if status.exitstatus == 2

        Master::Trace::Dmesg.status("hook0", "#{argv.first} faulted, exit #{status.exitstatus.inspect}; allowing", io: $stderr)
        nil
      rescue SystemCallError => e
        Master::Trace::Dmesg.status("hook0", "#{argv.first} not run, #{e.message}; allowing", io: $stderr)
        nil
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
