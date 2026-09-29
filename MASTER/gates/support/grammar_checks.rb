# frozen_string_literal: true

module Deploy
  class RenderedGeometryGate
    # Layout grammar: whether a surface says each of its parts once and says
    # them the same way. Two bars offering the same destinations, two search
    # fields, sections of one column that disagree about its width by a few
    # pixels, and a small action lost in a card that fills the screen.
    #
    # Included into PlacementChecks and run from its check_layout, because the
    # gate reaches every question about where things sit through that one
    # call. box_area comes from there too.
    module GrammarChecks
      def check_grammar(surface, data)
        elements = Array(data["elements"])
        check_duplicate_nav(surface, data)
        check_duplicate_search(surface, elements)
        check_width_drift(surface, data)
        check_lost_action(surface, elements)
      end

      # Two bars on the first screen sharing most of their destinations make
      # the reader choose a navigation before choosing a place. A bar inside a
      # bar is one navigation and its tablist, and a bar off the first screen
      # is a drawer or a footer, which repeat by design.
      NAV_OVERLAP = 0.8
      NAV_MIN_LINKS = 3

      def check_duplicate_nav(surface, data)
        bars = Array(data["groups"]).select do |group|
          group["onscreen"] && !group["nested"] && Array(group["hrefs"]).size >= NAV_MIN_LINKS
        end
        pairs = bars.combination(2).select { |a, b| shared_destinations(a["hrefs"], b["hrefs"]) >= NAV_OVERLAP }
        return if pairs.empty?

        @result.fail(
          "geometry duplicate_nav: #{surface.id} shows #{pairs.size} pair(s) of navigation offering the same " \
          "destinations — #{pairs.first(2).map { |a, b| "#{a["sel"]} and #{b["sel"]}" }.join('; ')} " \
          "(principle=consistency)", severity: :soft
        )
      end

      # Over the smaller bar: a tab bar whose every link is also in a longer
      # menu duplicates it, however many more the menu carries.
      def shared_destinations(a, b)
        smaller = [a.size, b.size].min
        smaller.zero? ? 0.0 : (a & b).size.to_f / smaller
      end

      def check_duplicate_search(surface, elements)
        fields = elements.select do |el|
          el["search"] && el["visible"] && el["onscreen"] && !el["input_type"].to_s.match?(NON_TEXT_INPUT)
        end
        return if fields.size < 2

        @result.fail(
          "geometry duplicate_search: #{surface.id} lays out #{fields.size} search fields — " \
          "#{fields.first(3).map { |el| el["key"] }.join('; ')} (principle=consistency)", severity: :soft
        )
      end

      # Under 2px is rounding, and a difference of a whole section gap or more
      # is an inset somebody chose. Between the two, sections that were meant to
      # share a column disagree about its width.
      ROUNDING_PX = 2

      def check_width_drift(surface, data)
        blocks = Array(data["main_blocks"])
        return if blocks.size < 3

        column = blocks.map { |block| block["w"].to_i }.tally.max_by { |width, count| [count, width] }.first
        gap = (@rules.dig("ultraminimalism", "negative_space", "section_gap_px") || 48).to_i
        drift = blocks.select { |block| (block["w"].to_i - column).abs.between?(ROUNDING_PX, gap - 1) }
        return if drift.empty?

        @result.fail(
          "geometry width_drift: #{surface.id} main holds a #{column}px column and #{drift.size} block(s) " \
          "a few pixels off it — #{drift.first(3).map { |b| "#{b["sel"]} #{b["w"]}px" }.join('; ')} " \
          "(principle=alignment)", severity: :soft
        )
      end

      # A card filling half the screen or more, holding one or two controls
      # that together cover under 2% of it, hides its only way forward in its
      # own margin. A card selector seen at two rects is a list, and a list
      # item's size is the list's decision, so those are left alone.
      LARGE_CARD_SHARE = 0.5
      LOST_ACTION_SHARE = 0.02
      LOST_ACTION_MAX_CONTROLS = 2

      def check_lost_action(surface, elements)
        lost = lone_cards(elements).select do |card, controls|
          area = card["w"].to_f * card["h"].to_f
          area >= surface.width.to_f * surface.height.to_f * LARGE_CARD_SHARE &&
            controls.size <= LOST_ACTION_MAX_CONTROLS && controls.sum { |el| box_area(el) } < area * LOST_ACTION_SHARE
        end
        return if lost.empty?

        named = lost.first(3).map do |card, controls|
          "#{card["sel"]} (#{card["w"]}x#{card["h"]}) holds #{controls.map { |el| el["key"] }.join(', ')}"
        end
        @result.fail(
          "geometry lost_action: #{surface.id} has #{lost.size} large card(s) whose only action is small — " \
          "#{named.join('; ')} (principle=fitts)", severity: :soft
        )
      end

      def lone_cards(elements)
        controls = elements.select { |el| el["card"] && el["interactive"] && el["visible"] && el["onscreen"] }
        by_selector = controls.group_by { |el| el["card"]["sel"] }
        listed = by_selector.select { |_sel, els| els.map { |el| el["card"] }.uniq.size > 1 }
        controls.reject { |el| listed.key?(el["card"]["sel"]) }.group_by { |el| el["card"] }
      end
    end
  end
end
