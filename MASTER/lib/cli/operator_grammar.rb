# frozen_string_literal: true

require "shellwords"

module Master
  module CLI
    # The deterministic operator grammar handles actions whose meaning is
    # unambiguous without a model; everything else falls through to the agent.
    module OperatorGrammar
      Interpretation = Data.define(:kind, :value)

      REPEAT = /\A(?:again|repeat)(?:\s+(?:that|it))?[.!?]*\z/i
      REPEAT_AGAIN = /\b(?:do|run)\s+(?:that|it)\s+again\b/i
      FOCUS = /\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i
      DIRECT_SHELL_ATOM = %r{\A(?:pwd|whoami|date(?:\s+-u)?|uname(?:\s+-[[:alnum:]-]+)?|ls(?:\s+(?:-[[:alnum:]-]+|[[:alnum:]_./~*-]+))*|git\s+(?:status(?:\s+--short)?|branch(?:\s+--show-current)?|rev-parse\s+--show-toplevel|diff\s+--stat|log\s+(?:-n\s+\d+\s+)?--oneline))\z}i.freeze
      SHELL_BUILTINS = %w[cd echo eval exec export false print printf pwd source type true unset whoami].freeze

      module_function

      def parse(input)
        text = input.to_s.strip
        return if text.start_with?("/")
        return Interpretation.new(:repeat, nil) if text.match?(REPEAT) || text.match?(REPEAT_AGAIN)
        return Interpretation.new(:toggle_focus, nil) if text.match?(FOCUS)
        return Interpretation.new(:direct_shell, text) if direct_shell?(text)
        nil
      end

      # The local operator is a shell user. Any command whose first executable
      # is actually available goes straight to the same governed zsh path as
      # other direct shell entrypoints; ordinary English still falls through to
      # the agent.
      def direct_shell?(command)
        parts = command.to_s.split(/\s+(?:&&|\|\||;|\|)\s+/)
        return false if parts.empty?

        parts.all? do |part|
          DIRECT_SHELL_ATOM.match?(part) || shell_command_name?(part)
        end
      end

      # A line that reads as prose is never shell, whatever its first word: on 2026-10-22 "what is the meaning of
      # life, honestly?" ran /usr/bin/what with six arguments, because `what` is installed. Prose ends in ? or !,
      # holds a comma, or runs four words or more with no flag, path, assignment, glob or file name among them.
      SHELL_ARGUMENT = %r{\A-|[/=~$*{}\[\]<>]|\.\w+\z}

      def prose?(text)
        return true if text.match?(/[?!]\s*\z|,\s/)

        words = text.split
        words.size >= 4 && words.drop(1).none? { |word| word.match?(SHELL_ARGUMENT) }
      end

      def shell_command_name?(part)
        return false if prose?(part)

        argv = Shellwords.split(part)
        name = argv.first.to_s
        return false if name.empty?

        basename = File.basename(name)
        return true if SHELL_BUILTINS.include?(basename)
        return true if name.start_with?("/")

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          candidate = File.join(dir, name)
          File.executable?(candidate) && !File.directory?(candidate)
        end
      rescue ArgumentError
        false
      end
    end
  end
end
