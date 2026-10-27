# frozen_string_literal: true

require "json"

module Master
  module Fix
    # One proposed stylesheet edit for the design loop: parsed from the model's
    # reply, checked against what the loop may change, and applied or undone on
    # disk. The loop changes layout (spacing, size, alignment, structure, text size
    # on a declared step) and never a rendered value: laws.yml RENDERED_VALUES
    # leaves colour, typeface, weight, shadow, opacity and the named layout tokens
    # to the operator, so those edits are refused here whatever the model asked for.
    class DesignEdit
      Refused = Class.new(StandardError)

      # The model's proposal.
      Proposal = Data.define(:file, :find, :replace, :why)

      # What may be checked beyond the text: guard ->(path, new_text) { refusal or nil }, the mechanical
      # laws judging the file as it would be written; scale, the declared spacing steps in px;
      # type_scale, the declared text sizes in px a font-size may take (none declared: none allowed);
      # classes, the class names the offered stylesheets define, which a view edit may add to an element.
      Rules = Data.define(:guard, :scale, :type_scale, :classes) do
        def initialize(guard:, scale:, type_scale: nil, classes: nil) = super
      end

      # font-size is the one font property the loop may set, and only to a declared step
      # (refuse_off_type_scale!): family, weight and the rest of the font shorthand stay the operator's.
      RENDERED_PROPERTY = /\A(?:color|background(?:-[a-z]+)*|font(?:-(?!size\z)[a-z]+)*|border(?:-[a-z]+)*-color|outline-color|
                              box-shadow|text-shadow|opacity|filter|fill|stroke|mix-blend-mode)\z/ix
      FONT_SIZE = "font-size"
      TYPE_STEP_PX = 1.0
      COLOUR_BEARING = /\A(?:border|outline)(?:-[a-z]+)?\z/i
      DECLARATION = /([a-z-]+)\s*:\s*([^;{}]+)/i
      TOKEN_FILE = %r{(?:_tokens|_dialect_tokens|design_tokens|/tokens)\.(?:scss|css|yml)\z}
      SPACING = /\A(?:margin|padding|gap|row-gap|column-gap|inset|top|right|bottom|left)(?:-[a-z]+)*\z/i
      LENGTH_PX = /(?<![\w.-])(-?\d*\.?\d+)(px|rem|em)\b/
      LENGTH = /-?\d*\.?\d+(?:px|r?em|ch|vh|vw|%)?/
      RULE_SELECTOR = /(?:\A|[};])\s*([^{};@]+)\{/
      UNIVERSAL = /(?:\A|[\s>+~,(])\*(?![\w-])/
      MAX_CHARS = 1_200
      NO_RULES = Rules.new(guard: nil, scale: nil)

      attr_reader :proposal

      def self.parse(reply, allowed:, rules: NO_RULES)
        data = JSON.parse(reply.to_s[/\{.*\}/m].to_s)
        file = allowed.find { |path| path == data["file"] || path.end_with?(data["file"].to_s) }
        text = ->(key) { data[key].to_s }
        proposal = Proposal.new(file:, find: text.("find"), replace: text.("replace"), why: text.("why").strip)
        (file.to_s.end_with?(".erb") ? MarkupEdit : self).new(proposal, rules)
      rescue JSON::ParserError
        raise Refused, "the reply was not a JSON edit (it began #{reply.to_s[0, 90].inspect})"
      end

      # The declared spacing steps, read once.
      def self.scale
        @scale ||= Array(Master.tokens.dig("scale", "space_px")).map(&:to_f)
      end

      def initialize(proposal, rules = NO_RULES)
        @proposal = proposal
        @rules = rules
      end

      def file = proposal.file

      # A view edit (MarkupEdit) changes markup and needs no stylesheet rebuild.
      def markup? = false

      def why = proposal.why

      def key = [file, proposal.find]

      # The classes and ids in the selector of the rule the edit sits in; empty when it
      # sits in a rule of plain element selectors or cannot be located.
      def selector_tokens
        text = File.read(file, encoding: "UTF-8")
        head = text[0, text.index(proposal.find).to_i]
        open = head.rindex("{")
        return [] unless open

        start = (head.rindex(/[};]/, open) || -1) + 1
        head[start...open].scan(/[.#][\w-]+/).uniq
      end

      # Raises Refused with the reason; returns the file's current text.
      def check!
        refuse_scope!
        text = File.read(file, encoding: "UTF-8")
        count = text.scan(proposal.find).size
        raise Refused, "the text to replace occurs #{count} times, not once" unless count == 1

        refuse_rendered_values!
        refuse_broad_rules!
        refuse_off_scale!
        refuse_off_type_scale!
        reason = @rules.guard&.call(file, text.sub(proposal.find) { proposal.replace })
        raise Refused, "the laws refuse it: #{reason}" if reason

        text
      end

      def apply!
        text = check!
        write(text.sub(proposal.find) { proposal.replace })
        text
      end

      def restore(original) = write(original)

      private

      def refuse_scope!
        raise Refused, "the file is not one of the offered sources" unless file
        if file.match?(TOKEN_FILE)
          raise Refused, "token values are operator-owned (RENDERED_VALUES), so token files are not edited"
        end
        raise Refused, "empty or unchanged edit" if proposal.find.empty? || proposal.find == proposal.replace
        return unless [proposal.find, proposal.replace].any? { |text| text.size > MAX_CHARS }

        raise Refused, "edit longer than #{MAX_CHARS} characters"
      end

      def refuse_rendered_values!
        raise Refused, "!important is not a layout fix" if important_added?

        bad = changed.find { |name, _| name.match?(RENDERED_PROPERTY) }
        raise Refused, "changes a rendered value (#{bad.join(': ')}), which the loop leaves to the operator" if bad
        raise Refused, "changes a border or outline colour" if colour_changed?
      end

      # A new rule has to name a class or id. `main > h1 ~ *` matched every element after
      # a heading on every page of an app, and only a few pages were re-measured.
      def refuse_broad_rules!
        selectors = ->(text) { text.scan(RULE_SELECTOR).flatten.map(&:strip) }
        broad = (selectors.(proposal.replace) - selectors.(proposal.find))
                .find { |selector| selector.match?(UNIVERSAL) || !selector.match?(/[.#]/) }
        raise Refused, "the rule `#{broad}` would match across the whole app; name a class or id" if broad
      end

      def important_added? = proposal.replace.include?("!important") && !proposal.find.include?("!important")

      # A spacing value the edit introduces must sit on the declared scale (px, or
      # rem/em at 16px), unless it is a token, calc or keyword: the 8px rhythm is a law.
      def refuse_off_scale!
        steps = @rules.scale || self.class.scale
        changed.each do |name, value|
          next unless name.match?(SPACING) && !value.include?("var(") && !value.include?("calc(")

          value.scan(LENGTH_PX).each do |number, unit|
            px = number.to_f * (unit == "px" ? 1 : 16)
            next if steps.include?(px.abs.round(2))

            raise Refused, "#{name}: #{number}#{unit} is off the declared spacing scale"
          end
        end
      end

      # A font-size the edit introduces must be a token or sit on a declared text step, and
      # may not be smaller than the size it replaces: a layout score that reads line length
      # in characters is also raised by shrinking text, which is not a layout fix.
      def refuse_off_type_scale!
        steps = Array(@rules.type_scale)
        before = declarations(proposal.find).to_h[FONT_SIZE]
        changed.each do |name, value|
          next unless name == FONT_SIZE
          next if value.match?(/\Avar\(\s*--text-[\w-]+\s*\)\z/)

          px = text_px(value)
          raise Refused, "font-size: #{value} is not a declared text size" unless px && steps.any? { |step| (step - px).abs <= TYPE_STEP_PX }

          was = before && text_px(before)
          raise Refused, "font-size: #{value} makes the text smaller than #{before}" if was && px < was - TYPE_STEP_PX
        end
      end

      def text_px(value)
        match = value.strip.match(/\A(\d*\.?\d+)(px|rem|em)\z/)
        match && match[1].to_f * (match[2] == "px" ? 1 : 16)
      end

      # Declarations the edit adds or alters.
      def changed =declarations(proposal.replace) - declarations(proposal.find)

      # [[property, value], ...] with whitespace squeezed, so a rule rewritten onto
      # one line compares equal to the same declarations on several.
      def declarations(text)
        text.scan(DECLARATION).map { |name, value| [name.downcase, value.strip.gsub(/\s+/, " ")] }
      end

      def colour_changed?
        old = declarations(proposal.find).to_h
        changed.select { |name, _| name.match?(COLOUR_BEARING) }.any? do |name, value|
          old[name].nil? || old[name].gsub(LENGTH, "") != value.gsub(LENGTH, "")
        end
      end

      def write(text)
        tmp = "#{file}.design-#{Process.pid}"
        File.write(tmp, text)
        File.rename(tmp, file)
      end
    end
  end
end

require_relative "markup_edit"
