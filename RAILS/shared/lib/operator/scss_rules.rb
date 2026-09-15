# frozen_string_literal: true

module Operator
  # The rule a declaration sits in, read out of SCSS source.
  #
  # Each app compiles from one application.scss, so a check can no longer scope
  # itself by file: "the nav sheet declares a tap floor" and "no vertical sheet
  # re-sets --accent" have no sheet left to name. The selector is the scope that
  # survives. It says which element a declaration styles wherever the rule sits,
  # and it stays true when the file is reordered.
  #
  # A lexer rather than a regex, because the three things that break a brace
  # count are all common here: comments that quote a rule, strings such as
  # [data-controller*="live-search"], and interpolation such as
  # body.vertical-#{$v}, whose braces are not blocks.
  #
  # Arrays of characters throughout. Indexing a String is linear once it holds a
  # multibyte character, and every stylesheet here carries an em dash, so a
  # String-indexed pass over brgen's file does not finish.
  module ScssRules
    Rule = Data.define(:selector, :parents, :body, :line, :end_line, :range) do
      def at_rule? = selector.start_with?("@")

      # The selector list, split on the commas that separate selectors rather
      # than the ones inside :is() or an attribute value.
      def selectors = ScssRules.split_list(selector)

      # Each selector resolved against its enclosing rules, so a nested
      # `.section` under `#navBar` reads as `#navBar .section`.
      def full_selectors
        parents.reject { |parent| parent.start_with?("@") }.reverse.reduce(selectors) do |children, parent|
          ScssRules.split_list(parent).product(children).map do |outer, inner|
            inner.include?("&") ? inner.gsub("&", outer) : "#{outer} #{inner}"
          end
        end
      end

      def declares?(pattern) = body.match?(pattern)
    end

    STRUCTURAL = %w[{ } ;].freeze

    module_function

    # Every block in source order, style rules and at-rules alike, each holding
    # its own declarations and none of its nested blocks'.
    def rules(source)
      structure, text = lex(source)
      found = []
      stack = []
      prelude_at = 0
      line = 1
      structure.each_with_index do |char, index|
        if char == "{"
          stack << { prelude: squish(text[prelude_at...index].join), start: prelude_at, open: index, line:, children: [] }
        elsif char == "}" && (frame = stack.pop)
          found << close(text, frame, index, stack, line)
          stack.last[:children] << (frame[:start]..index) if stack.last
        end
        line += 1 if char == "\n"
        prelude_at = index + 1 if STRUCTURAL.include?(char)
      end
      found.sort_by { |rule| rule.range.begin }
    end

    # Style rules any of whose selectors match, nested ones resolved.
    def matching(source, pattern)
      rules(source).reject(&:at_rule?).select { |rule| rule.full_selectors.any? { |selector| selector.match?(pattern) } }
    end

    # The source with every style rule whose selectors all match blanked to
    # spaces, newlines kept, so a check that reads lines still names the right one.
    def without(source, pattern)
      chars = source.chars
      covered(source, pattern).each do |range|
        range.each { |index| chars[index] = " " unless chars[index] == "\n" }
      end
      chars.join
    end

    # The source cut into runs, each paired with whether its rules all match, so
    # a rewrite can touch one kind and hand the other back byte for byte.
    def partition(source, pattern)
      chars = source.chars
      runs = []
      cursor = 0
      covered(source, pattern).each do |range|
        runs << [chars[cursor...range.begin].join, false] if range.begin > cursor
        runs << [chars[range].join, true]
        cursor = range.end + 1
      end
      runs << [chars[cursor..].join, false] if cursor < chars.length
      runs
    end

    # The outermost ranges of style rules whose selectors all match. A nested
    # match inside one already covered adds nothing.
    def covered(source, pattern)
      rules(source).reject(&:at_rule?)
                   .select { |rule| rule.full_selectors.all? { |selector| selector.match?(pattern) } }
                   .each_with_object([]) do |rule, ranges|
        ranges << rule.range unless ranges.last&.cover?(rule.range.begin)
      end
    end

    def split_list(selector)
      parts = [+""]
      depth = 0
      quote = nil
      selector.each_char do |char|
        if quote
          quote = nil if char == quote
        elsif char == '"' || char == "'"
          quote = char
        elsif "([".include?(char)
          depth += 1
        elsif ")]".include?(char)
          depth -= 1
        elsif char == "," && depth.zero?
          parts << +""
          next
        end
        parts.last << char
      end
      parts.map(&:strip).reject(&:empty?)
    end

    def squish(text) = text.gsub(/\s+/, " ").strip

    def close(text, frame, index, stack, end_line)
      pieces = []
      cursor = frame[:open] + 1
      frame[:children].each do |child|
        pieces << text[cursor...child.begin].join
        cursor = child.end + 1
      end
      pieces << text[cursor...index].join
      Rule.new(selector: frame[:prelude], parents: stack.map { |outer| outer[:prelude] },
               body: squish(pieces.join), line: frame[:line], end_line:, range: frame[:start]..index)
    end

    # Two character arrays the length of the source. `text` has comments
    # blanked; `structure` also blanks every brace and semicolon inside a
    # string, a url() or an interpolation, so only real block edges remain.
    def lex(source) = Lexer.new(source).run

    # One method per state, each returning the index of the last character it
    # consumed. A state that hands its character to another returns one short.
    class Lexer
      def initialize(source)
        @chars = source.chars
        @structure = @chars.dup
        @text = @chars.dup
        @state = nil
        @depth = 0
      end

      def run
        index = 0
        index = step(index) + 1 while index < @chars.length
        [@structure, @text]
      end

      private

      def step(index)
        case @state
        when nil then code(index)
        when :line_comment then line_comment(index)
        when :block_comment then block_comment(index)
        when :url then url(index)
        when :interpolation then interpolation(index)
        else string(index)
        end
      end

      def code(index)
        char, after = @chars[index], @chars[index + 1]
        if char == "/" && (after == "*" || (after == "/" && @chars[index - 1] != ":"))
          @state = after == "*" ? :block_comment : :line_comment
          return index - 1
        end
        return open_interpolation(index) if char == "#" && after == "{"

        @state = char if char == '"' || char == "'"
        return index unless @chars[index, 4].join == "url("

        @state = :url
        index + 3
      end

      def open_interpolation(index)
        hide(@structure, index + 1)
        @depth = 1
        @state = :interpolation
        index + 1
      end

      def line_comment(index)
        @state = nil if @chars[index] == "\n"
        hide(@text, index)
        hide(@structure, index)
        index
      end

      def block_comment(index)
        closing = @chars[index] == "*" && @chars[index + 1] == "/"
        (closing ? [index, index + 1] : [index]).each do |at|
          hide(@text, at)
          hide(@structure, at)
        end
        @state = nil if closing
        closing ? index + 1 : index
      end

      def string(index)
        char = @chars[index]
        hide(@structure, index) if STRUCTURAL.include?(char)
        return index + 1 if char == "\\"

        @state = @depth.positive? ? :interpolation : nil if char == @state
        index
      end

      def url(index)
        hide(@structure, index) if STRUCTURAL.include?(@chars[index])
        @state = nil if @chars[index] == ")"
        index
      end

      def interpolation(index)
        char = @chars[index]
        hide(@structure, index) if STRUCTURAL.include?(char)
        @state = char if char == '"' || char == "'"
        @depth += { "{" => 1, "}" => -1 }.fetch(char, 0)
        @state = nil if @depth.zero?
        index
      end

      def hide(copy, at)
        copy[at] = " " unless copy[at] == "\n"
      end
    end
  end
end
