# frozen_string_literal: true

# Lexes a command line into words and operators, the way the shell splits it, closely enough to find
# command positions. Substitutions ($(...), backticks, <(...)) are collected and checked on their own.
# Io::GnuTextTools is its reader.
module Master
  module Io
    class ShellLexer

      # The constructs that hand the lexer a second command line or a word that is not a command:
      # substitutions, process substitutions and redirects.
      module Substitutions
        # A quoted span counts as one piece, so a parenthesis inside quotes never moves the depth.
        PAREN_PIECES = /'[^']*'?|"[^"]*"?|[()]|[^'"()]+/
        PAREN_DEPTH = { "(" => 1, ")" => -1 }.freeze
        REDIRECT_CHARS = %w[< > & |].freeze

        private

        def backtick
          @nested << enclosed("`")
          append("_")
        end

        def dollar
          return append_char unless peek(1) == "("

          @nested << balanced
          append("_")
        end

        def angle
          return redirect unless peek(1) == "("

          finish_word
          @nested << balanced
        end

        # The text inside the parenthesis after the current character, moving past its match.
        def balanced
          open = @pos + 1
          close = paren_close(open)
          @pos = close + 1
          @src[(open + 1)...close].to_s
        end

        def paren_close(open)
          depth = 0
          offset = open
          @src[open..].scan(PAREN_PIECES) do |piece|
            depth += PAREN_DEPTH.fetch(piece, 0)
            return offset if depth.zero?

            offset += piece.length
          end
          @src.length
        end

        # `2>&1`, `> out`, `<< EOF`, `<<< word`: the fd digits and the target are not command words.
        def redirect
          @word = nil if @word&.match?(/\A\d+\z/)
          finish_word

          @pos += 1 while REDIRECT_CHARS.include?(peek)
          if @src[@pos - 1] == "&" && peek&.match?(/[\d-]/)
            @pos += 1
          else
            @skip_next_word = true
          end
        end
      end

      # Escapes and quotes: what they enclose is a word's value, never an operator.
      module Quoting
        private

        def escape
          following = peek(1).to_s
          append(following) unless following == "\n"
          @pos += 2
        end

        # The text from here to the next `char`, moving past it.
        def enclosed(char)
          start = @pos + 1
          close = @src.index(char, start) || @src.length
          @pos = close + 1
          @src[start...close]
        end

        # Inside double quotes only substitutions run; everything else is the word's value.
        def double_quoted
          @pos += 1
          instance_exec(&QUOTED_HANDLERS.fetch(peek, QUOTED_PLAIN)) until done? || peek == '"'
          @pos += 1
        end

        def quoted_escape
          append(peek(1).to_s)
          @pos += 2
        end
      end

      include Substitutions
      include Quoting

      OPERATORS = ["&&", "||", "|&", ";;", "|", ";", "&", "(", ")", "\n"].freeze

      # One handler per character that starts something other than a plain word character; each runs on
      # the lexer. Inside double quotes only escapes and substitutions are special.
      HANDLERS = {
        " " => proc { blank }, "\t" => proc { blank }, "#" => proc { comment }, "\\" => proc { escape },
        "'" => proc { append(enclosed("'")) }, '"' => proc { double_quoted }, "`" => proc { backtick },
        "$" => proc { dollar }, "<" => proc { angle }, ">" => proc { angle }
      }.freeze
      PLAIN = proc { operator_or_char }

      QUOTED_HANDLERS = { "\\" => proc { quoted_escape }, "`" => proc { backtick }, "$" => proc { dollar } }.freeze
      QUOTED_PLAIN = proc { append_char }

      # A heredoc body is data: its lines become blank so the lexer never reads them as commands.
      def self.blank_heredoc_bodies(command)
        terminator = nil
        lines = command.lines.map do |line|
          if terminator
            terminator = nil if line.strip == terminator
            next "\n"
          end

          terminator = line[/<<-?\s*['"]?(\w+)['"]?/, 1] unless line.include?("<<<")
          line
        end
        lines.join
      end

      attr_reader :tokens, :nested

      def initialize(src)
        @src = self.class.blank_heredoc_bodies(src)
        @pos = 0
        @tokens = []
        @nested = []
        @word = nil
        @skip_next_word = false

        step until done?
        finish_word
      end

      private

      # No endless defs in this file: a hook may run under macOS's /usr/bin/ruby 2.6, a hook that fails to
      # parse does not block, and every banned tool then passes.
      def step
        instance_exec(&HANDLERS.fetch(peek, PLAIN))
      end

      def done?
        @pos >= @src.length
      end

      def peek(offset = 0)
        @src[@pos + offset]
      end

      def append(text)
        @word ||= +""
        @word << text
      end

      def append_char
        append(peek)
        @pos += 1
      end

      def finish_word
        return unless @word

        @tokens << [:word, @word] unless @skip_next_word
        @skip_next_word = false
        @word = nil
      end

      def blank
        finish_word
        @pos += 1
      end

      # A # starts a comment only at the start of a word; inside one it is an ordinary character.
      def comment
        if @word then append_char
        else @pos += 1 until done? || peek == "\n"
        end
      end

      def operator_or_char
        operator = OPERATORS.find { |candidate| @src[@pos, candidate.length] == candidate }

        if operator
          finish_word
          @tokens << [:op, operator]
          @pos += operator.length
        else
          append_char
        end
      end
    end
  end
end
