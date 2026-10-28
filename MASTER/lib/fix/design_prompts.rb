# frozen_string_literal: true

module Master
  module Fix
    # The words the design loop says to the model: the edit request and the
    # before-and-after comparison. A mixin, because both read the loop's current
    # round (@target, @page_tokens, @undone).
    module DesignPrompts
      SOURCE_CHARS = 12_000

      VARIANTS = [
        "Change as little as possible.",
        "Reach it through a different selector or property than the obvious one.",
        "Prefer an existing token or layout primitive over a new value.",
      ].freeze

      DIRECTION = "Flat, brutalist, Swiss: one sans family, a strict 8px rhythm, tap targets of at least 44px, " \
                  "clear hierarchy, nothing decorative (no gradients, shadows or ornament)."

      private

      # The house floor above, then what the design layer says this surface is for. The loop
      # judges against the same direction, typeface rule and composition the /fix critic and
      # fixer already hold a frontend file to, not a second copy of them.
      def direction
        surface = @target[:surface]
        language = Master::Design::VisualLanguage
        brief = language.direction_lines(surface, language.direction_for(surface)).strip
        rule = Master::Design::Typeface::HOUSE_RULE if Master::Design::Authoring.house_typeface?(surface)
        [DIRECTION, brief, rule].compact.join("\n")
      end

      # One line of the same for the comparison, which judges two pictures and needs no brief.
      def direction_summary
        surface = @target[:surface]
        language = Master::Design::VisualLanguage
        "#{DIRECTION} This page: #{language.purpose_for(surface)} (#{language.direction_for(surface)})."
      end

      def vision_prompt
        <<~TEXT
          Two renders of the same page, A then B. Direction: #{direction_summary}
          Which has the better layout: clearer hierarchy, steadier spacing, nothing cramped or floating?
          Say "same" if you cannot tell them apart.
          Return only JSON: {"better": "A" or "B" or "same", "why": "<one short sentence>"}.
        TEXT
      end

      def prompt(sources, variant)
        <<~TEXT
          The image is the current render of #{@target[:surface].id}.
          Its layout score is #{@target[:score].round(1)} of 100.
          Weakest measures (0 to 1): #{weakest_measures}.
          Elements the checks flagged (kind: element keys): #{@target[:offender_keys].inspect}.
          The largest elements on this page, as key [x y w h]:
          #{page_map}
          Edit a rule whose selector matches one of these classes or ids, or it will change nothing you can see.
          All classes and ids on the page: #{@page_tokens.first(80).join(' ')}.
          Direction: #{direction}
          Make ONE edit to ONE of the stylesheets below that improves the layout you can see: spacing, alignment,
          sizing, hierarchy, grid or flex structure, overflow, reading width. Change layout properties only, never
          a colour, typeface, font weight, shadow or opacity, never a token file, and keep every spacing value on the
          declared scale or a var(--token).
          #{type_note}
          #{markup_note(sources)}
          #{VARIANTS[variant % VARIANTS.size]}
          #{undone_note}
          Return only JSON: {"file": "<one path below>", "find": "<exact text from that file, occurring once>",
          "replace": "<new text>", "why": "<one short sentence>"}.

          #{sources.map { |path| "FILE #{path}\n#{File.read(path, encoding: 'UTF-8')[0, SOURCE_CHARS]}" }.join("\n\n")}
        TEXT
      end

      MAP_ROWS = 20

      # The biggest boxes on the page: where a layout edit can be seen.
      def page_map
        els = Array(@target[:payload]["elements"]).select { |e| e["rect"] && e["visible"] != false }
        big = els.max_by(MAP_ROWS) { |e| e["rect"]["w"].to_f * e["rect"]["h"].to_f }
        big.map { |e| "#{e['key']} #{e['rect'].values_at('x', 'y', 'w', 'h').map { |v| v.to_f.round }}" }.join("\n          ")
      end

      def weakest_measures
        subs = LayoutScoreStore.measure(@plan.root, @target[:payload]).subs
        weakest = subs.sort_by { |_, value| value.to_f }.first(3)
        weakest.map { |name, value| "#{name} #{value&.round(2)}" }.join(", ")
      end

      # A font-size may be set to a declared step and never made smaller; with no steps declared it may not be set.
      def type_note
        steps = type_steps.map { |px| px.round(2).to_s.delete_suffix(".0") }
        return "Do not set a font-size." if steps.empty?

        "A font-size may be set only to one of these px steps, or a var(--text-*) token, and never made smaller: #{steps.join(', ')}."
      end

      # A view is offered beside the stylesheets and may only gain classes those stylesheets define.
      def markup_note(sources)
        return "" unless sources.any? { |path| path.end_with?(".erb") }

        "A view (.erb) may be edited only to ADD class names, defined in the stylesheets below, to an element's " \
          'static class="..." attribute: never its text, ERB tags, tags or existing class names.'
      end

      def undone_note
        return "" if @undone.empty?

        "Tried and undone, with the reason: #{@undone.last(4).join(' | ')}. Do something different."
      end

    end
  end
end
