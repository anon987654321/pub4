# frozen_string_literal: true

require "yaml"
require_relative "shell_lexer"

module Master
  module Io
    # Which banned commands a shell line would run: data/laws.yml
    # `zsh.banned_commands`, judged one way for every reader. Io::Shell refuses a
    # line MASTER's own agents send, tools/block_gnu_text_tools.rb refuses one a
    # coding harness sends through its PreToolUse hook, and the ZSH_NATIVE_PATTERNS
    # Law reports one written into a script.
    #
    # The hook used to carry its own BANNED hash beside the law's list, and the two
    # had drifted: the law bans bash, the hook did not. Io::Shell matched `\bsed\b`
    # anywhere in a line and only published a warning, so `git commit -m "drop sed"`
    # warned and `sed -i` ran. One list, one lexer, three readers.
    #
    # Stdlib only, and no Master boot: the hook runs before every shell call a
    # harness makes and loads this file on its own, so the caller names the law
    # file (Master::LAWS_PATH inside MASTER).
    #
    # Looking only at the word after | ; & ( $( or a backtick misses `do wc`, `{ head`,
    # `! wc`, `xargs sed`, `timeout 5 awk`, `FOO=1 awk`, `/usr/bin/sed`, `gsed`,
    # `python3.12`, `zsh -c 'cut ...'` and `ssh vm23 'tail -f ...'`. So the line is
    # lexed into simple commands, walked past assignments, reserved words and
    # wrappers to the real command name, and what sh -c and ssh are handed is
    # checked again. Quoted words, heredoc bodies, comments and redirect targets
    # are data and never trip it.
    class GnuTextTools
      RESERVED = %w[if then else elif fi do done while until for in case esac select function time ! { } [[ ]]].freeze
      SHELLS = %w[sh bash zsh ksh dash].freeze
      ASSIGNMENT = /\A[A-Za-z_]\w*(\[[^\]]*\])?=/

      # Wrappers run the command that follows them. Each entry lists the flags that take a value.
      WRAPPERS = {
        "env" => %w[-u -C -S], "exec" => %w[-a], "command" => [], "builtin" => [], "noglob" => [],
        "nohup" => [], "sudo" => %w[-u -g -C -D -h -p -U], "doas" => %w[-u -C], "nice" => %w[-n],
        "timeout" => %w[-s -k --signal --kill-after], "xargs" => %w[-n -I -J -L -P -d -E -s -R -S],
        "caffeinate" => %w[-t -w], "stdbuf" => %w[-i -o -e]
      }.freeze

      # The bare operand a wrapper takes before its command: timeout's duration, nice's old-style increment.
      WRAPPER_OPERANDS = { "timeout" => /\A[\d.]+[smhd]?\z/, "nice" => /\A-?\d+\z/ }.freeze
      SSH_VALUE_FLAGS = %w[-b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w].freeze
      MAX_DEPTH = 4

      def self.load(laws_path)
        new(YAML.safe_load_file(laws_path, aliases: true).fetch("zsh"))
      end

      attr_reader :banned

      # A banned command without a replacement row is a law that refuses without
      # saying what to write, so it does not load.
      def initialize(section)
        @banned = Array(section.fetch("banned_commands")).map(&:to_s).freeze
        @replacements = Array(section.fetch("forbidden_commands"))
                        .to_h { |row| [row.fetch("command").to_s, row.fetch("replacement").to_s] }.freeze
        missing = @banned - @replacements.keys
        raise ArgumentError, "zsh.forbidden_commands has no replacement for #{missing.join(', ')}" unless missing.empty?
      end

      def replacement(name) = @replacements.fetch(name)

      # The banned commands the line runs, each named once, in the order found.
      def banned_in(src, depth = 0)
        return [] if depth > MAX_DEPTH

        lexer = ShellLexer.new(src.to_s)
        found = lexer.nested.flat_map { |inner| banned_in(inner, depth + 1) }
        simple_commands(lexer.tokens).each { |words| found.concat(banned_in_argv(command_words(words), depth)) }
        found.uniq
      end

      def refusal(names)
        lines = ["zsh law: #{names.join(', ')} refused (MASTER/data/laws.yml zsh.banned_commands)."]
        names.each { |name| lines << "  #{name}: #{replacement(name)}" }
        lines << "  Search with git grep; read files with the Read tool; one meaningful operation per line."
        lines.join("\n")
      end

      private

      # GNU names (gsed, gawk) and versioned interpreters (python3.12, perl5.36) reduce to the base name.
      def canonical(word)
        name = File.basename(word).sub(/\Apython[\d.]*\z/, "python").sub(/\Aperl[\d.]*\z/, "perl")
        bare = name.delete_prefix("g")
        name.start_with?("g") && banned.include?(bare) ? bare : name
      end

      def simple_commands(tokens)
        groups = tokens.slice_when { |left, right| left.first == :op || right.first == :op }
        groups.reject { |group| group.first.first == :op }.map { |group| group.map(&:last) }
      end

      # Walks past assignments, reserved words and wrappers to the command a simple command actually runs.
      def command_words(words)
        words = words.dup
        loop do
          words.shift while words.first&.match?(ASSIGNMENT) || RESERVED.include?(words.first)
          head = words.first
          return words unless head && WRAPPERS.key?(File.basename(head))

          skip_wrapper(words, head)
        end
      end

      def skip_wrapper(words, head)
        name = File.basename(head)
        value_flags = WRAPPERS.fetch(name)
        words.shift
        while (width = flag_width(words.first, value_flags, env: head == "env")).positive?
          words.shift(width)
        end

        operand = WRAPPER_OPERANDS[name]
        words.shift if operand && words.first&.match?(operand)
      end

      # How many words a wrapper's leading flag occupies: two for a flag with a value, none past the flags.
      def flag_width(flag, value_flags, env:)
        return 0 unless flag
        return 2 if value_flags.include?(flag)

        flag.start_with?("-") || (env && flag.include?("=")) ? 1 : 0
      end

      # The remote command of `ssh [opts] host cmd...`, joined the way ssh joins it.
      def ssh_remote(args)
        args = args.dup
        while (flag = args.first)&.start_with?("-")
          args.shift
          args.shift if SSH_VALUE_FLAGS.include?(flag)
        end

        args.shift
        args.join(" ")
      end

      # The command string a shell runs with -c, or ssh runs remotely; nil for any other command.
      def inner_command(name, argv)
        return ssh_remote(argv.drop(1)) if name == "ssh"
        return unless SHELLS.include?(name)

        flag = argv.index { |word| word.match?(/\A-\w*c\w*\z/) }
        argv[flag + 1].to_s if flag
      end

      def banned_in_argv(argv, depth)
        return [] if argv.empty?

        name = canonical(argv.first)
        found = banned.include?(name) ? [name] : []
        inner = inner_command(name, argv)
        found.concat(banned_in(inner, depth + 1)) if inner
        found
      end
    end
  end
end
