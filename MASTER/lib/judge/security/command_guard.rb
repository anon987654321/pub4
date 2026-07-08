# frozen_string_literal: true

require "open3"

module Master
  module Judge
    module Security
      module CommandGuard
        BANNED_COMMANDS = %w[sed awk tr grep cut head tail find wc sudo perl ruby dd xargs].freeze
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
