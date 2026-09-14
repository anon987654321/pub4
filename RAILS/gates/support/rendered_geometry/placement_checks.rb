# frozen_string_literal: true

require_relative "grammar_checks"

module Deploy
  class RenderedGeometryGate
    # Placement and weight, not size: whether a control is anywhere a person
    # would look, and whether the eye reaches it before something else. Hick's
    # law on how many peer choices a bar offers, Gestalt proximity on whether a
    # block's insides are further apart than its neighbours, the thumb zone on
    # a phone, the weak bottom-left corner of an F-pattern scan, the one box
    # that outweighs the rest of the screen, and a secondary action heavier
    # than the primary beside it.
    #
    # Split out along a seam the gate already carried as a banner comment.
    # Everything left in rendered_geometry.rb asks whether an element is big
    # enough, legible enough or on the grid; these ask where it sits and how
    # hard it pulls. They are also the only checks that read design_rules'
    # ux_laws, layout_rules.reading_patterns, layout_rules.whitespace and
    # typography.hierarchy sections.
    #
    # A module included back into the gate, like TokenChecks beside it, so it
    # keeps @rules and @result. Nothing here builds a path from __dir__ and
    # nothing here is resolved at load time — the design_metrics split moved a
    # css_budget.yml path one directory deeper and silently ran that gate
    # unbudgeted.
    module PlacementChecks
      # The layout grammar asks the same kind of question — is this part where
      # and as often as it should be — so it runs from check_layout as well.
      include GrammarChecks

      # Placement is about *the* primary action, not every control. CRITICAL is
      # deliberately broad — it matches any `btn` — which is right for "did this
      # control get occluded" and wrong here, where it would flag a secondary
      # ghost button in a page header as a stranded primary CTA.
      PRIMARY_ACTION = /\b(?:btn--primary|btn-primary|compose-trigger|compose-submit|
                            listing-buy-bar|cta|submit)\b/x

      # Indexed selectors (`a.nav_link[3]`) and card/list ancestry mark a repeated
      # item. Its position in the viewport is an accident of how far the page is
      # scrolled, not a placement decision anyone made, so the weak-area and
      # thumb-zone rules do not apply to it.
      REPEATED_ITEM = /\[\d+\]|feed-card|\bli\.|\barticle\b|card\b/

      # A submit button at the end of its own form is where a person looks for it.
      # The weak-area rule is about page-level placement — where the eye lands
      # when it arrives — not about flow inside a form it is already reading.
      IN_FORM = /(?:^|>)form[.\#>]|>form$/

      # layout_rules.touch.thumb_zone_primary_actions is bottom_center, and the
      # stated action is to flag critical mobile interactions in unreachable top
      # corners. Only meaningful on a phone-sized viewport held in one hand.
      THUMB_ZONE_MAX_WIDTH = 480

      def check_layout(surface, data)
        elements = Array(data["elements"])
        check_choice_overload(surface, data)
        check_proximity(surface, data)
        check_thumb_zone(surface, elements)
        check_scan_path(surface, elements)
        check_dominance(surface, elements)
        check_action_weight(surface, elements)
        check_grammar(surface, data)
      end

      # Hick's law: time to choose grows with the number of peer choices. The rule
      # is about what is offered at one moment, so a horizontally scrolling rail
      # is exempt — it is progressive disclosure, which is the prescribed remedy
      # rather than a violation of it.
      def check_choice_overload(surface, data)
        warn_at = @rules.dig("ux_laws", "hick", "nav_items_warn").to_i
        max_choices = @rules.dig("ux_laws", "hick", "max_visible_choices").to_i
        return if warn_at <= 0 && max_choices <= 0

        Array(data["groups"]).each do |group|
          # The largest chunk when the bar labels its sections, the total when it
          # does not. Hick is about peers at one decision level, and a labelled
          # role=group is a level — the same argument the scrollable exemption
          # above makes for a rail. Counting every link in a chunked bar credits
          # neither remedy and reports a number no reader ever faces.
          chunks = Array(group["chunks"]).map(&:to_i).reject(&:zero?)
          count = chunks.any? ? chunks.max : group["count"].to_i
          next if count <= max_choices || group["scrollable"]

          over = warn_at.positive? && count > warn_at
          @result.fail(
            "geometry choices: #{surface.id} #{group["sel"]} offers #{count} peer choices " \
            "(#{over ? "over nav_items_warn #{warn_at}" : "over max_visible_choices #{max_choices}"}) " \
            "with no progressive disclosure (principle=hick)",
            severity: over ? :hard : :soft
          )
        end
      end

      # layout_rules.whitespace.internal_not_greater_than_external — the measurable
      # form of Gestalt proximity. If a block's own padding is larger than the gap
      # to the next block, its insides are further apart than it is from its
      # neighbour, and the eye groups across the boundary instead of within it.
      # This is the rule that decides whether a card reads as one thing.
      def check_proximity(surface, data)
        return unless @rules.dig("layout_rules", "whitespace", "internal_not_greater_than_external")

        offenders = Array(data["proximity"]).select { |row| row["pad"].to_i > row["gap"].to_i }
        return if offenders.empty?

        # A card sitting flush against the next one (gap 0) is a deliberate
        # seamless list, not a proximity inversion.
        offenders = offenders.reject { |row| row["gap"].to_i.zero? }
        return if offenders.empty?

        worst = offenders.max_by(3) { |row| row["pad"].to_i - row["gap"].to_i }
        @result.fail(
          "geometry proximity: #{surface.id} has #{offenders.size} block(s) spaced wider inside than out — " \
          "#{worst.map { |r| "#{r["sel"]} (children #{r["pad"]}px apart, #{r["gap"]}px to the next block)" }.join('; ')}. " \
          "Their own parts read as further apart than they are from their neighbour (principle=proximity)",
          severity: :soft
        )
      end

      def placement_candidates(elements)
        elements.select do |el|
          next false unless el["interactive"] && el["visible"] && el["onscreen"] && el["frect"]
          next false unless el["key"].to_s.match?(PRIMARY_ACTION)
          next false if el["key"].to_s.match?(REPEATED_ITEM)
          # Fixed chrome follows the scroll, so it is reachable by definition.
          !%w[fixed sticky].include?(el["position"])
        end
      end

      def check_thumb_zone(surface, elements)
        return unless @rules.dig("layout_rules", "touch", "thumb_zone_primary_actions").to_s == "bottom_center"
        return if surface.width.to_i > THUMB_ZONE_MAX_WIDTH

        vw = surface.width.to_f
        vh = surface.height.to_f
        stranded = placement_candidates(elements).select do |el|
          r = el["frect"]
          cx = r["x"].to_f + r["w"].to_f / 2
          cy = r["y"].to_f + r["h"].to_f / 2
          cy < vh * 0.25 && (cx < vw * 0.25 || cx > vw * 0.75)
        end
        return if stranded.empty?

        @result.fail(
          "geometry thumb_zone: #{surface.id} puts #{stranded.size} primary action(s) in an unreachable " \
          "top corner — #{stranded.first(3).map { |el| el["key"] }.join('; ')} " \
          "(principle=thumb_zone)", severity: :soft
        )
      end

      # layout_rules.reading_patterns names bottom_left the weak area — the last
      # place an F- or Z-pattern scan reaches. A primary action parked there is
      # findable only by hunting.
      def check_scan_path(surface, elements)
        weak = @rules.dig("layout_rules", "reading_patterns", "weak_area").to_s
        return unless weak == "bottom_left"

        vw = surface.width.to_f
        vh = surface.height.to_f
        buried = placement_candidates(elements).reject { |el| el["key"].to_s.match?(IN_FORM) }.select do |el|
          r = el["frect"]
          cx = r["x"].to_f + r["w"].to_f / 2
          cy = r["y"].to_f + r["h"].to_f / 2
          cy > vh * 0.75 && cx < vw * 0.25
        end
        return if buried.empty?

        @result.fail(
          "geometry scan_path: #{surface.id} puts #{buried.size} primary action(s) in the weak " \
          "bottom-left area — #{buried.first(3).map { |el| el["key"] }.join('; ')} (principle=reading_patterns)",
          severity: :soft
        )
      end

      # More than half of the first screen's visual weight in one box is a page
      # with one thing on it, and that thing ought to be what the page is for.
      DOMINANT_SHARE = 0.5

      # A share is a comparison, and two painted boxes are a pair rather than a
      # hierarchy: 60/40 between a header and a button says nothing.
      MIN_WEIGHED_BOXES = 3

      # A box covering most of the viewport is the ground the others sit on, not
      # a figure competing with them. The shell, main and a full-bleed section
      # would otherwise win every surface they paint.
      GROUND_SHARE = 0.6

      # A share of a quiet page is not weight. The heaviest box has to be at
      # least as heavy as a twentieth of the screen painted at 21:1 — weight is
      # area times (contrast - 1), so that is one screen's area — before its
      # share means anything; a #1a1a1a header on black is 80% of nothing.
      MIN_DOMINANT_WEIGHT_SCREENS = 1.0

      # Visual weight is how hard a box pulls the eye before anything in it is
      # read: the screen it covers times how far its own fill stands from what
      # it sits on. Images and canvases carry weight too and the probe does not
      # walk them, so this reads painted boxes only and says less than it could.
      def check_dominance(surface, elements)
        screen = surface.width.to_f * surface.height.to_f
        weighed = elements.filter_map do |el|
          next unless el["visible"] && el["onscreen"]

          area = onscreen_area(el, surface)
          next if area >= screen * GROUND_SHARE

          weight = area * (fill_contrast(el) - 1)
          [el, weight] if weight.positive?
        end
        return if weighed.size < MIN_WEIGHED_BOXES

        heaviest, weight = weighed.max_by(&:last)
        share = weight / weighed.sum(&:last)
        return if weight < screen * MIN_DOMINANT_WEIGHT_SCREENS
        return if share <= DOMINANT_SHARE || intended_focus?(heaviest)

        @result.fail(
          "geometry dominance: #{surface.id} #{heaviest["key"]} carries #{(share * 100).round}% of the visual " \
          "weight of #{weighed.size} painted boxes on the first screen and is neither the primary action " \
          "nor the h1 (principle=hierarchy)", severity: :soft
        )
      end

      # A secondary control that out-weighs the primary beside it asks the reader
      # to take the other road. Weight has three axes — box size, fill contrast
      # and font weight — and a secondary is reported only when it wins two and
      # loses none, so a trade (larger but paler) stays a design decision.
      def check_action_weight(surface, elements)
        buttons = elements.select { |el| el["visible"] && el["onscreen"] && el["parent"] && button_like?(el) }
        primaries, secondaries = buttons.partition { |el| el["key"].to_s.match?(PRIMARY_ACTION) }
        inverted = primaries.flat_map do |primary|
          secondaries.select { |el| el["parent"] == primary["parent"] && outweighs?(el, primary) }
                     .map { |el| "#{el["key"]} over #{primary["key"]}" }
        end
        return if inverted.empty?

        @result.fail(
          "geometry action_weight: #{surface.id} has #{inverted.size} secondary action(s) heavier than the " \
          "primary beside them — #{inverted.uniq.first(3).join('; ')} (principle=hierarchy)", severity: :soft
        )
      end

      BUTTON_INPUTS = %w[submit button].freeze
      BUTTON_KEY = /\b(?:btn|button)\b/

      def button_like?(el)
        el["tag"] == "button" || el["role"] == "button" || BUTTON_INPUTS.include?(el["input_type"]) ||
          el["key"].to_s.split(">").last.to_s.match?(BUTTON_KEY)
      end

      def outweighs?(secondary, primary)
        weight_wins(secondary, primary).size >= 2 && weight_wins(primary, secondary).empty?
      end

      # A step smaller than the one typography.hierarchy treats as the least
      # visible difference between two levels is not a win on that axis.
      def weight_wins(a, b)
        step = (@rules.dig("typography", "hierarchy", "min_size_ratio_between_levels") || 1.2).to_f
        delta = (@rules.dig("typography", "hierarchy", "min_weight_delta") || 200).to_i
        wins = []
        wins << :size if box_area(a) > box_area(b) * step
        wins << :contrast if fill_contrast(a) > fill_contrast(b) * step
        wins << :font_weight if a["font_weight"].to_i >= b["font_weight"].to_i + delta
        wins
      end

      def intended_focus?(el)
        el["key"].to_s.match?(PRIMARY_ACTION) || el["tag"] == "h1"
      end

      # 1.0 for a box that paints no field of its own: it adds no contrast to
      # what is already under it.
      def fill_contrast(el)
        return 1.0 unless el["fill"] && el["bg"] && el["under"]

        DesignMetrics.contrast_ratio(el["bg"], el["under"]) || 1.0
      end

      def box_area(el)
        r = el["frect"] || {}
        r["w"].to_f * r["h"].to_f
      end

      def onscreen_area(el, surface)
        r = el["frect"] || {}
        w = [r["x"].to_f + r["w"].to_f, surface.width.to_f].min - [r["x"].to_f, 0].max
        h = [r["y"].to_f + r["h"].to_f, surface.height.to_f].min - [r["y"].to_f, 0].max
        w.positive? && h.positive? ? w * h : 0.0
      end
    end
  end
end
