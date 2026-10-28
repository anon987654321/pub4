# frozen_string_literal: true

module Master
  module Fix
    # Flattens a SCSS (or plain CSS) source into its style rules, each with the
    # selectors Sass would emit and the exact character span it occupies, so a
    # rule can be matched to rendered coverage and later cut out of the file.
    #
    # It is a scanner, not a Sass compiler: comments are blanked in place (offsets
    # stay valid), `&` is resolved against the parent selectors, and anything it
    # cannot flatten exactly (interpolation, placeholders) is marked `dynamic`
    # and never judged. Blocks that hold no style rules (@keyframes, @mixin,
    # @font-face, ...) are skipped whole.
    module ScssRules
      Rule = Data.define(:selectors, :file, :start, :stop, :line, :end_line, :leaf, :dynamic, :context)

      SKIPPED = /\A@(?:-\w+-)?(?:keyframes|font-face|mixin|function|property|page|counter-style|font-feature-values)\b/
      Frame = Struct.new(:kind, :selectors, :start, :prelude, :child_rule, :context, keyword_init: true)

      module_function

      def parse(source, file: "")
        text = blank_comments(source)
        rules = []
        stack = []
        buf_start = nil
        i = 0
        while i < text.length
          ch = text[i]
          case ch
          when '"', "'"
            buf_start ||= i
            i = skip_string(text, i)
            next
          when "#"
            if text[i + 1] == "{"
              buf_start ||= i
              i = skip_interpolation(text, i)
              next
            end
          when "{"
            open_block(text, stack, buf_start || i, i)
            buf_start = nil
          when "}"
            close_block(source, text, stack, rules, file, i)
            buf_start = nil
          when ";"
            buf_start = nil
          end
          buf_start ||= i unless ch.match?(/\s/) || %w[{ } ;].include?(ch)
          i += 1
        end
        rules
      end

      # Selectors with nesting resolved, split at top-level commas.
      def flatten(prelude, parents)
        own = split_list(prelude)
        return own if parents.empty?

        parents.flat_map do |parent|
          own.map { |sel| sel.include?("&") ? sel.gsub("&", parent) : "#{parent} #{sel}" }
        end
      end

      def split_list(text)
        parts = []
        depth = 0
        current = +""
        text.each_char do |c|
          depth += 1 if "([".include?(c)
          depth -= 1 if ")]".include?(c)
          if c == "," && depth.zero?
            parts << current.strip
            current = +""
          else
            current << c
          end
        end
        parts << current.strip
        parts.reject(&:empty?)
      end

      # One spelling for a selector so Sass output and source compare equal.
      def normalize(selector)
        selector.gsub(/\s*([>+~,])\s*/, '\1').gsub(/\s+/, " ").strip
      end

      # Class and id names a selector requires of an element. Names under :not()
      # and inside attribute brackets are conditions, not requirements.
      def required_names(selector)
        plain = selector.gsub(/\[[^\]]*\]/, "").gsub(/:not\((?:[^()]|\([^()]*\))*\)/, "")
        plain.scan(/(?<![\w-])([.#])(-?[A-Za-z_][\w-]*)(?!\()/).map { |kind, name| [kind, name] }
      end

      def blank_comments(source)
        out = source.dup
        out.gsub!(%r{/\*.*?\*/}m) { |m| m.gsub(/[^\n]/, " ") }
        out.gsub!(%r{(?<![:"'(])//[^\n]*}) { |m| " " * m.length }
        out
      end

      def skip_string(text, start)
        quote = text[start]
        i = start + 1
        i += (text[i] == "\\" ? 2 : 1) while i < text.length && text[i] != quote && text[i] != "\n"
        i + 1
      end

      def skip_interpolation(text, start)
        depth = 0
        i = start + 1
        while i < text.length
          depth += 1 if text[i] == "{"
          depth -= 1 if text[i] == "}"
          return i + 1 if depth.zero?

          i += 1
        end
        i
      end

      def open_block(text, stack, from, at)
        prelude = text[from...at].strip
        rule_parent = stack.reverse.find { |f| f.kind == :rule }
        parent_selectors = stack.reverse.find { |f| f.selectors }&.selectors || []
        if stack.any? { |f| f.kind == :skip } || prelude.match?(SKIPPED) || prelude.end_with?(":")
          stack << Frame.new(kind: :skip)
        elsif prelude.start_with?("@")
          stack << Frame.new(kind: :neutral, selectors: parent_selectors.empty? ? nil : parent_selectors,
                             context: [stack.reverse.find(&:context)&.context, prelude[/\A@\w+[^{]*/]].compact.join(" ").strip)
        else
          rule_parent&.child_rule = true
          stack << Frame.new(kind: :rule, selectors: flatten(prelude, parent_selectors), start: from, prelude:,
                             context: stack.reverse.find(&:context)&.context)
        end
      end

      def close_block(source, _text, stack, rules, file, at)
        frame = stack.pop or return
        return unless frame.kind == :rule

        dynamic = frame.prelude.include?('#{') || frame.prelude.include?("%") || frame.selectors.any? { |s| s.include?('#{') }
        rules << Rule.new(selectors: frame.selectors, file:, start: frame.start, stop: at + 1,
                          line: source[0...frame.start].count("\n") + 1,
                          end_line: source[0..at].count("\n") + 1,
                          leaf: !frame.child_rule, dynamic:, context: frame.context)
      end
    end
  end
end
