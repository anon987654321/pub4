# frozen_string_literal: true

require "open3"

module Master
  module Judge
    module Security
      module CommandGuard
        # Any of these can trivially reintroduce whatever the rest of this list tries to
        # prevent (bash -c 'sed ...', curl ... | sh, python -c '...') -- a token-level
        # blocklist is a weak boundary in general, but omitting the shells/interpreters/
        # network fetchers themselves defeats the point of having one at all.
        BANNED_COMMANDS = %w[
          sed awk tr grep cut head tail find wc sudo doas perl ruby python python3 dd xargs
          bash sh zsh csh ksh fish curl wget nc ncat telnet
        ].freeze
        TOKEN_SPLIT = /\s+|[|&;<>()]/

        module_function

        def validate_command!(args)
          tokens = Array(args).flat_map { |arg| arg.to_s.split(TOKEN_SPLIT) }
          tokens.each do |token|
            cleaned = token.downcase.strip
            next if cleaned.empty?

            raise Master::SecurityError, "Banned terminal execution vector: #{cleaned}" if BANNED_COMMANDS.include?(cleaned)
          end
          true
        end

        def secure_execute(args, chdir: Dir.pwd)
          validate_command!(args)
          clean_env = { "LANG" => "C", "LC_ALL" => "C" }
          stdout_and_stderr, status = Master::Reach::Exec.capture2e(clean_env, *Array(args), chdir: chdir)
          return Result.ok(stdout_and_stderr) if status.success?

          Result.err(stdout_and_stderr, category: :infrastructure)
        rescue Master::SecurityError => e
          Result.err(e.message, category: :validation)
        rescue StandardError => e
          Result.err(e.message, category: :infrastructure)
        end
      end
    end
  end
end
