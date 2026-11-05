# frozen_string_literal: true

require "prism"

module Master
  module Content

    # The operator's rule of 2026-11-05: punctuation is ASCII everywhere, in
    # code, comments, docs, logs and the copy a visitor reads. One mark per
    # meaning (SINGULARITY_one_true_mark): a hyphen, not a hyphen and two
    # dashes; three dots, not a glyph that looks like them. Letters are not
    # punctuation, so æ, ø and å stay.
    #
    # The banned characters are written as escapes here, so this file obeys
    # the Law it defines.
    module AsciiPunctuation
      DOUBLE_QUOTE = '"'
      SINGLE_QUOTE = "'"
      RIGHT_ARROW = "->"
      LEFT_ARROW = "<-"

      REPLACEMENTS = {
        "\u2014" => "-", "\u2013" => "-", "\u00B7" => "-", "\u2022" => "-",
        "\u2026" => "...",
        "\u201C" => DOUBLE_QUOTE, "\u201D" => DOUBLE_QUOTE, "\u2018" => SINGLE_QUOTE, "\u2019" => SINGLE_QUOTE,
        "\u2192" => RIGHT_ARROW, "\u2190" => LEFT_ARROW,
        "\u00D7" => "x", "\u2265" => ">=", "\u2264" => "<="
      }.freeze

      BANNED = Regexp.union(REPLACEMENTS.keys).freeze

      # An em dash, middle dot or bullet sits between words as a pause, so it
      # becomes a spaced hyphen; at a line's start it is a list marker, "- ".
      SEPARATOR = /([ \t]*)[\u2014\u00B7\u2022]([ \t]*)/

      # Beside a quote, a bracket or a tag edge the hyphen takes no space on that side.
      OPENERS = ['"', "'", "(", "[", "{", "<", ">", "`"].freeze
      CLOSERS = ["\n", "\r", '"', "'", ")", "]", "}", "<", ">", "`"].freeze

      module_function

      def banned?(text) = text.match?(BANNED)

      # The first banned character in text and what replaces it, or nil.
      def first(text)
        char = text[BANNED]
        char && [char, REPLACEMENTS.fetch(char)]
      end

      # before and after name the characters around text when text is a piece
      # of something larger, such as a string fragment ending at an
      # interpolation; a mark at the piece's edge is spaced by its real
      # neighbour, not by the edge.
      def rewrite(text, before: nil, after: nil)
        text.gsub(SEPARATOR) { separator(Regexp.last_match, before:, after:) }.gsub(BANNED, REPLACEMENTS)
      end

      def separator(match, before: nil, after: nil)
        before = match.pre_match.empty? ? before : match.pre_match[-1]
        after = match.post_match.empty? ? after : match.post_match[0]
        "#{lead(match[1], before)}-#{trail(match[2], after)}"
      end

      # Space the writer put beside the mark stays, since a literal such as
      # " - " used as a join or the indent before a list marker means it.
      # Where there was none, the neighbour decides.
      def lead(space, before)
        return space unless space.empty?

        before.nil? || before == "\n" || OPENERS.include?(before) ? "" : " "
      end

      def trail(space, after)
        return space unless space.empty? || ["\n", "\r"].include?(after)

        after.nil? || CLOSERS.include?(after) ? "" : " "
      end
    end

    # Ruby source rewritten to ASCII punctuation without changing what it does.
    # A comment or a string a person reads becomes ASCII. A mark the program
    # handles as data, in a regex, a gsub or split argument, a when branch or a
    # mapping table, is kept as a \u escape, so the bytes at runtime stay
    # what they were. Answers nil when the result would not parse, or when a
    # data mark sits in a literal that cannot hold an escape.
    module AsciiPunctuationRuby
      DATA_CALLS = (%w[
        gsub gsub! sub sub! tr tr! tr_s delete delete! squeeze count include? index rindex split
        start_with? end_with? match? match scan partition rpartition eql? delete_prefix bad
        delete_suffix chomp lstrip rstrip strip
      ] + ["==", "!=", "===", "=~"]).freeze

      Segment = Data.define(:range, :mode, :delimiter)

      module_function

      # all_data: every literal is data, for a file whose subject is the marks themselves.
      def rewrite(source, all_data: false)
        return source unless AsciiPunctuation.banned?(source)

        result = Prism.parse(source)
        return unless result.success?

        out = apply(source, segments(result, all_data:))
        out && Prism.parse(out).success? ? out : nil
      end

      def segments(result, all_data: false)
        found = result.comments.map { |comment| Segment.new(comment.location, :prose, nil) }
        found << Segment.new(result.data_loc, :prose, nil) if result.data_loc
        literals = []
        result.value.accept(Literals.new(literals, all_data:))
        found + literals
      end

      # Edits from the end backwards, so earlier byte offsets stay valid.
      def apply(source, segments)
        bytes = source.b
        segments.sort_by { |segment| -segment.range.start_offset }.each do |segment|
          range = segment.range.start_offset...segment.range.end_offset
          text = bytes.byteslice(range).force_encoding(Encoding::UTF_8)
          next unless AsciiPunctuation.banned?(text)

          replacement = replace(text, segment, **edges(bytes, range)) or return nil
          bytes[range] = replacement.b
        end
        bytes.force_encoding(Encoding::UTF_8)
      end

      # A string fragment that meets an interpolation is mid-sentence: the
      # words go on past its edge, so a dash there keeps its space. Any other
      # edge (a quote, a line end) is the edge of the text.
      def edges(bytes, range)
        before = range.begin.positive? ? bytes.byteslice(range.begin - 1, 1) : nil
        after = bytes.byteslice(range.end, 2).to_s
        { before: before == "}" ? "x" : nil, after: after.start_with?("\#{", "\#@") ? "x" : nil }
      end

      CURLY = /[\u2018\u2019\u201C\u201D]/

      def replace(text, segment, before: nil, after: nil)
        return escape(text, segment.delimiter) if segment.mode == :data

        ascii = AsciiPunctuation.rewrite(text, before:, after:)
        quote = segment.delimiter
        return ascii unless %w[' "].include?(quote) && text.match?(CURLY)

        requote(text, quote, before:, after:)
      end

      # A curly quote that becomes the literal's own delimiter needs a backslash.
      def requote(text, quote, before: nil, after: nil)
        text.gsub(AsciiPunctuation::SEPARATOR) { AsciiPunctuation.separator(Regexp.last_match, before:, after:) }
            .gsub(AsciiPunctuation::BANNED) do |mark|
              ascii_mark = AsciiPunctuation::REPLACEMENTS.fetch(mark)
              ascii_mark == quote ? "\\#{quote}" : ascii_mark
            end
      end

      # Single-quoted literals keep no escapes, so a data mark there is a person's call.
      def escape(text, delimiter)
        return if delimiter == "'"

        text.gsub(AsciiPunctuation::BANNED) { |mark| format("\\u%04X", mark.ord) }
      end

      # Every literal Prism sees, marked :data where the program reads its marks.
      class Literals < Prism::Visitor
        def initialize(found, all_data: false)
          super()
          @found = found
          @data = all_data ? 1 : 0
          @delimiters = [nil]
        end

        def visit_call_node(node)
          return super unless DATA_CALLS.include?(node.name.to_s)

          receiver, arguments, block = node.receiver, node.arguments, node.block
          visit(receiver) if receiver
          as_data { visit(arguments) if arguments }
          visit(block) if block
        end

        def visit_when_node(node)
          as_data { node.conditions.each { |condition| visit(condition) } }
          visit(node.statements) if node.statements
        end

        # A pair whose key is nothing but banned marks is a mapping table.
        def visit_assoc_node(node)
          marks_only?(node.key) ? as_data { super } : super
        end

        # %w and %i hold no escapes; %W and %I do.
        # An array of nothing but marks is a character set the program reads.
        def visit_array_node(node)
          opening = node.opening_loc&.slice.to_s
          marks = node.elements.any? && node.elements.all? { |element| marks_only?(element) }
          return (marks ? as_data { super } : super) unless opening.start_with?("%")

          within(opening.match?(/\A%[wi]/) ? "'" : "\"") { marks ? as_data { super } : super }
        end

        def visit_regular_expression_node(node) = record(node.content_loc, :data, delimiter: "/")

        def visit_interpolated_regular_expression_node(node)
          within("/") { as_data { super } }
        end

        def visit_interpolated_string_node(node)
          within(node.opening_loc&.slice.to_s[0] == "<" ? "<<" : node.opening_loc&.slice) { super }
        end

        def visit_string_node(node)
          opening = node.opening_loc&.slice
          data = @data.positive? || regex_source?(node.content_loc.slice)
          record(node.content_loc, data ? :data : :prose, delimiter: delimiter_of(opening))
        end

        def visit_symbol_node(node)
          record(node.value_loc, :prose, delimiter: delimiter_of(node.opening_loc&.slice)) if node.value_loc
        end

        private

        # A string that is a piece of a regex (a group, a class, an escape) is data.
        REGEX_SOURCE = /\(\?[:=!<]|\\[sdwbAzS]|\[\^/

        def regex_source?(text) = text.match?(REGEX_SOURCE)

        def marks_only?(node)
          node.is_a?(Prism::StringNode) && node.unescaped.valid_encoding? && AsciiPunctuation.banned?(node.unescaped) &&
            node.unescaped.gsub(AsciiPunctuation::BANNED, "").strip.empty?
        end

        def delimiter_of(opening)
          return @delimiters.last if opening.nil?
          return "'" if opening == "'" || opening.start_with?("%q") || opening.match?(/\A<<[~-]?'/)
          return '"' if opening == '"' || opening == ':"'

          opening
        end

        def record(location, mode, delimiter: nil)
          @found << Segment.new(location, mode, delimiter)
        end

        def as_data
          @data += 1
          yield
        ensure
          @data -= 1
        end

        def within(delimiter)
          @delimiters.push(delimiter)
          yield
        ensure
          @delimiters.pop
        end
      end
    end
  end
end
