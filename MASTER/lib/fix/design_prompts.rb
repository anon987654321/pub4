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

      def vision_prompt
        <<~TEXT
          Two renders of the same page, A then B. Direction: #{DIRECTION}
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
          Elements the gates flagged (kind: element keys): #{@target[:offender_keys].inspect}.
          The largest elements on this page, as key [x y w h]:
          #{page_map}
          Edit a rule whose selector matches one of these classes or ids, or it will change nothing you can see.
          All classes and ids on the page: #{@page_tokens.first(80).join(' ')}.
          Direction: #{DIRECTION}
          Make ONE edit to ONE of the stylesheets below that improves the layout you can see: spacing, alignment,
          sizing, hierarchy, grid or flex structure, overflow, reading width. Change layout properties only, never
          a colour, font, shadow or opacity, never a token file, and keep every spacing value on the declared
          scale or a var(--token).
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

      def undone_note
        return "" if @undone.empty?

        "Tried and undone, with the reason: #{@undone.last(4).join(' | ')}. Do something different."
      end

    end
  end
end
