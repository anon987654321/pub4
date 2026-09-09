# frozen_string_literal: true

module Deploy
  class RenderedGeometryGate
    # Placement, not size: whether a control is anywhere a person would look.
    # Hick's law on how many peer choices a bar offers, Gestalt proximity on
    # whether a block's insides are further apart than its neighbours, the
    # thumb zone on a phone, and the weak bottom-left corner of an F-pattern
    # scan.
    #
    # Split out along a seam the gate already carried as a banner comment.
    # Everything left in rendered_geometry.rb asks whether an element is big
    # enough, legible enough or on the grid; these four ask where it sits. They
    # are also the only checks that read design_rules' ux_laws,
    # layout_rules.reading_patterns and layout_rules.whitespace sections.
    #
    # A module included back into the gate, like TokenChecks beside it, so it
    # keeps @rules and @result. Nothing here builds a path from __dir__ and
    # nothing here is resolved at load time — the design_metrics split moved a
    # css_budget.yml path one directory deeper and silently ran that gate
    # unbudgeted.
    module PlacementChecks
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
    end
  end
end
