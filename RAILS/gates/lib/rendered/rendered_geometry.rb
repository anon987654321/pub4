# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"
require_relative "../../support/geometry_autofix"
require_relative "../../support/gate_autofix"
require_relative "../../support/design_metrics"

module Deploy
  # Rendered-geometry contracts: Fitts, occlusion, overflow, computed contrast,
  # token conformance, 8px rhythm — all measured in a real browser.
  #
  # The gate that layout_geometry was named after and did not do. That one is
  # FirstScreenGate now, named for what it actually asserts: a skip link, a main
  # landmark, an h1, and a tap minimum declared in SCSS — all of it text. A tap
  # minimum on an element that is overlapped, clipped or overridden at this
  # breakpoint satisfies it and fails here, because here the box is measured.
  #
  # Both are worth keeping. That one runs in seconds without Chrome and is the
  # floor; this one needs a browser and a booted app and is the assertion.
  class RenderedGeometryGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    MASTER_RULES = File.join(ROOT, "MASTER", "data", "rules.yml")
    TOKENS = File.join(RAILS_ROOT, "shared", "design_tokens.yml")

    # Controls whose failure costs the user the interaction outright. Everything
    # else reports soft so one noisy surface cannot wall off the merge.
    CRITICAL = /\b(btn|button|submit|tab-item|tab-bar|feed-action|swipe-action|deal-fav|
                  compose-submit|listing-buy-bar|channel-composer|cta)\b/x

    def self.run
      return run_once unless GateAutofix.enabled?

      GateAutofix.remeasure_loop(
        measure: -> { run_once },
        apply: ->(result) { GeometryAutofix.apply(result.autofix_findings, dry: GateAutofix.dry_run?) },
        label: "geometry_autofix"
      )
    end

    def self.run_once = new.run

    # GateResult carrying structured findings for the geometry autofixer.
    class Result < GateResult
      def autofix_findings = (@autofix_findings ||= [])

      def autofix(app:, selector:, kind:, detail: nil)
        autofix_findings << { app: app, selector: selector, kind: kind, detail: detail }
      end
    end

    def run
      @result = Result.new
      @rules = ((YAML.safe_load_file(MASTER_RULES, aliases: true) if File.file?(MASTER_RULES)) || {})["design_rules"] || {}
      @tokens = File.file?(TOKENS) ? YAML.safe_load_file(TOKENS) : {}
      @min_touch = (@rules.dig("layout_rules", "touch", "target_min_px") || 44).to_f
      @aaa = (@rules.dig("typography", "accessibility", "normal_text_contrast") || 7.0).to_f
      # design_rules states the spacing grid twice and the two disagree:
      # pixel_perfection.eight_px_rhythm allows 12 and 20, layout_rules.grid.
      # allowed_spacing_px does not. css_constitution, rhythm_lint and
      # design_metrics all read the first; only this gate read the second, so a
      # 12px gap was simultaneously compliant and a violation depending on which
      # gate you asked. It is also the value --space-3 declares, which settles
      # which list is real. Same precedence as design_metrics: rhythm first,
      # grid as the fallback.
      @allowed_spacing = Array(@rules.dig("pixel_perfection", "eight_px_rhythm")).map(&:to_i)
      if @allowed_spacing.empty?
        @allowed_spacing = Array(@rules.dig("layout_rules", "grid", "allowed_spacing_px")).map(&:to_i)
      end
      @allowed_spacing = [4, 8, 16, 24, 32, 48, 64] if @allowed_spacing.empty?
      @palette = token_palette

      unless GeometryProbe.available?
        @result.inconclusive!("geometry: no Chrome/Chromium — rendered geometry not measured (set CHROME_PATH)")
        return @result
      end

      surfaces = GeometryProbe.surfaces
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("geometry: #{app} port closed — surfaces skipped")
      end
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("geometry: no app reachable — nothing measured")
        return @result
      end

      probed = 0
      GeometryProbe.each_payload(live) do |surface, payload|
        if payload["error"]
          @result.fail("geometry: #{surface.id} probe failed — #{payload["error"]}")
          next
        end
        probed += 1
        check_surface(surface, payload)
      end
      # What was actually measured, so a gate that measured some surfaces and
      # skipped others is not reported as having measured nothing.
      @result.checked!(probed)
      @result.warn("geometry: measured #{probed} surface×viewport cells in a real browser")
      @result
    end

    private

    def check_surface(surface, data)
      status = data["status"].to_i
      unless status.zero? || status.between?(200, 399)
        @result.fail("geometry: #{surface.id} served HTTP #{status} at #{surface.url} — design checks skipped " \
                     "(a 403 host-authorization or 500 page is measurable but meaningless)")
        return
      end

      elements = Array(data["elements"])
      check_landmarks(surface, data)
      check_overflow(surface, data)
      check_fitts(surface, elements)
      check_occlusion(surface, elements)
      check_chrome_occlusion(surface, elements)
      check_contrast(surface, elements)
      check_token_conformance(surface, data)
      check_choice_overload(surface, data)
      check_proximity(surface, data)
      check_thumb_zone(surface, elements)
      check_scan_path(surface, elements)
      check_input_zoom(surface, elements)
      check_subpixel(surface, elements)
      check_edge_alignment(surface, elements)
      check_target_spacing(surface, elements)
      check_centered_prose(surface, elements)
      check_rhythm(surface, data, GeometryType.check(@result, surface, data))
    end

    # Everything above this line reads the rounded rect, which is the one number
    # a subpixel defect cannot survive: an element laid out at x=12.5 reports 13
    # and measures as aligned. The four checks below read `frect`, the unrounded
    # rect the probe now also returns.

    # Placement, not size. Everything else in this gate asks whether an element
    # is big enough, legible enough or on the grid; these four ask whether it is
    # anywhere sensible — the questions design_rules states under ux_laws,
    # layout_rules.reading_patterns and layout_rules.whitespace, and which
    # nothing read.

    # Hick's law: time to choose grows with the number of peer choices. The rule
    # is about what is offered at one moment, so a horizontally scrolling rail
    # is exempt — it is progressive disclosure, which is the prescribed remedy
    # rather than a violation of it.
    def check_choice_overload(surface, data)
      warn_at = @rules.dig("ux_laws", "hick", "nav_items_warn").to_i
      max_choices = @rules.dig("ux_laws", "hick", "max_visible_choices").to_i
      return if warn_at <= 0 && max_choices <= 0

      Array(data["groups"]).each do |group|
        count = group["count"].to_i
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

    def placement_candidates(elements)
      elements.select do |el|
        next false unless el["interactive"] && el["visible"] && el["onscreen"] && el["frect"]
        next false unless el["key"].to_s.match?(PRIMARY_ACTION)
        next false if el["key"].to_s.match?(REPEATED_ITEM)
        # Fixed chrome follows the scroll, so it is reachable by definition.
        !%w[fixed sticky].include?(el["position"])
      end
    end

    # layout_rules.touch.thumb_zone_primary_actions is bottom_center, and the
    # stated action is to flag critical mobile interactions in unreachable top
    # corners. Only meaningful on a phone-sized viewport held in one hand.
    THUMB_ZONE_MAX_WIDTH = 480

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

    # The rendered half of design_metrics' mobile_input check, and the half that
    # can actually be complete. The source check has to infer "this is a text
    # field" from the selector, so a rule written as `#q { … }` or one that only
    # inherits its size is invisible to it — which is exactly how bsdports'
    # search field sat at 13.5px. Here the tag is known and the size is the one
    # the browser computed, root scaling and inheritance included.
    TEXT_INPUT_TAGS = %w[input textarea select].freeze
    NON_TEXT_INPUT = /\A(?:radio|checkbox|range|color|file|submit|button|image|hidden)\z/

    def check_input_zoom(surface, elements)
      floor = (@rules.dig("typography", "accessibility", "mobile_input_min_px") || 16).to_f
      return if floor <= 0

      offenders = elements.select do |el|
        next false unless TEXT_INPUT_TAGS.include?(el["tag"])
        next false unless el["visible"] && el["onscreen"]
        # A submit button is an <input> too, and it takes no caret.
        next false if el["input_type"].to_s.match?(NON_TEXT_INPUT)

        size = el["font_size"].to_f
        size.positive? && size < floor
      end
      return if offenders.empty?

      named = offenders.uniq { |el| el["key"] }.first(4)
                       .map { |el| "#{el["key"]} at #{el["font_size"]}px" }
      @result.fail(
        "geometry input_zoom: #{surface.id} renders #{offenders.size} text field(s) under " \
        "#{floor.to_i}px — #{named.join('; ')}. iOS Safari zooms the viewport on focus and does " \
        "not zoom back (principle=accessibility)"
      )
    end

    # A box on a fractional pixel is resampled by the compositor: text loses its
    # hinting and a 1px border becomes two half-intensity lines. It is the most
    # common cause of "this looks slightly soft" that no stylesheet explains,
    # because the offending value is usually a percentage or a flex remainder
    # rather than anything written down.
    SUBPIXEL_TOLERANCE = 0.05

    def fractional?(value)
      return false if value.nil?

      frac = value.to_f.abs % 1
      frac > SUBPIXEL_TOLERANCE && frac < (1 - SUBPIXEL_TOLERANCE)
    end

    def check_subpixel(surface, elements)
      offenders = elements.select do |el|
        next false unless el["visible"] && el["onscreen"]

        r = el["frect"]
        next false unless r
        # An element laid out by the width of the text before it is fractional
        # by construction — a row of nav links lands at 85.5, 148.38, 201.66
        # because that is where the words end, and no stylesheet chose it.
        # Resampling only shows as a seam on a box that paints an edge, so this
        # asks about block-level boxes and leaves inline runs alone.
        next false if el["display"].to_s.start_with?("inline") && el["display"] != "inline-block"
        next false if r["w"].to_f < 24 || r["h"].to_f < 24

        # Width and height are excluded deliberately: an intrinsically sized box
        # is allowed to be 100.5px wide. It is the *position* that resamples the
        # paint, and the position is what a layout controls.
        fractional?(r["x"]) || fractional?(r["y"])
      end
      return if offenders.empty?

      # Report distinct components, not instances. A feed of forty cards sharing
      # one mispositioned action row is one thing to fix, and counting it forty
      # times buries the other nine.
      by_key = offenders.group_by { |el| el["key"] }
      named = by_key.first(5).map do |key, els|
        r = els.first["frect"]
        "#{key} at (#{r["x"]}, #{r["y"]})#{" x#{els.size}" if els.size > 1}"
      end
      @result.fail(
        "geometry subpixel: #{surface.id} paints #{by_key.size} distinct component(s) on fractional " \
        "pixels (#{offenders.size} instances) — #{named.join('; ')} (principle=pixel_perfection)",
        severity: :soft
      )
    end

    # Two stacked blocks whose left edges differ by a pixel or three read as a
    # mistake to anyone looking at the page, and no source rule can see it: the
    # two values live in different stylesheets and are individually defensible.
    # Exact agreement is fine and full disagreement is usually deliberate
    # indentation. It is the near miss that is always a bug.
    NEAR_MISS = (0.5..4.0)

    def check_edge_alignment(surface, elements)
      majors = elements.select do |el|
        r = el["frect"]
        el["visible"] && el["onscreen"] && r && r["w"].to_f >= surface.width * 0.4
      end
      return if majors.size < 2

      edges = majors.map { |el| [el["frect"]["x"].to_f, el] }.sort_by(&:first)
      misses = edges.each_cons(2).filter_map do |(x1, a), (x2, b)|
        delta = (x2 - x1).abs
        next unless NEAR_MISS.cover?(delta)

        "#{a["key"]} at #{x1} vs #{b["key"]} at #{x2} (#{delta.round(2)}px apart)"
      end
      return if misses.empty?

      @result.fail(
        "geometry alignment: #{surface.id} has #{misses.size} near-miss left edge(s) — " \
        "#{misses.first(4).join('; ')}. Align them or separate them deliberately " \
        "(principle=alignment)", severity: :soft
      )
    end

    # WCAG 2.5.8. The rule is *conditional*, and the condition is the whole
    # point: a target at least 24x24 CSS px is exempt no matter how close its
    # neighbour is, because a finger that lands anywhere on it still hits it.
    # Only undersized targets need clearance. Measured without that condition
    # this reported 3283 pairs on one page — every adjacent feed action, all of
    # them adequately sized and none of them a defect.
    WCAG_TARGET_MIN = 24.0

    def undersized?(rect)
      rect["w"].to_f < WCAG_TARGET_MIN || rect["h"].to_f < WCAG_TARGET_MIN
    end

    # The probe's own inline_in_text flag only catches a link whose parent is
    # running text. It misses the commonest shape here — a link inside a card
    # body, which is still a sentence — so the structural signal decides it: a
    # box no taller than its own line of text has no padding of its own and is
    # therefore a text run, not a control someone sized.
    def inline_target?(el)
      return true if el["inline_in_text"]
      return false unless el["tag"] == "a" && !el["text"].to_s.strip.empty?

      lh = el["line_height"].to_f
      lh = el["font_size"].to_f * 1.5 if lh <= 0
      return false if lh <= 0

      el["frect"]&.dig("h").to_f <= lh + 2
    end

    def check_target_spacing(surface, elements)
      targets = elements.select do |el|
        r = el["frect"]
        next false unless el["interactive"] && el["visible"] && el["onscreen"]
        next false unless r && r["w"].to_f.positive? && r["h"].to_f.positive?

        # 2.5.8 exempts targets "in a sentence or whose size is otherwise
        # constrained by the line-height of non-target text". Counting those
        # flags every pair of adjacent links in a paragraph, which is not a
        # defect and is not fixable without breaking the sentence.
        !inline_target?(el)
      end
      return if targets.size < 2

      crowded = []
      targets.combination(2) do |a, b|
        # Exempt unless the pair actually needs clearance.
        next unless undersized?(a["frect"]) || undersized?(b["frect"])

        gap = rect_gap(a["frect"], b["frect"])
        # Nested or overlapping controls are occlusion, already reported by
        # check_occlusion; only true neighbours count here.
        next if gap.nil? || gap.negative? || gap >= WCAG_TARGET_MIN

        crowded << "#{a["key"]} (#{a["frect"]["w"].to_i}x#{a["frect"]["h"].to_i}) and " \
                   "#{b["key"]} (#{b["frect"]["w"].to_i}x#{b["frect"]["h"].to_i}) are #{gap.round(1)}px apart"
      end
      return if crowded.empty?

      @result.fail(
        "geometry target_spacing: #{surface.id} has #{crowded.size} undersized target pair(s) closer " \
        "than #{WCAG_TARGET_MIN.to_i}px — #{crowded.first(3).join('; ')} (principle=fitts)", severity: :soft
      )
    end

    # Edge-to-edge distance between two boxes; nil when they overlap on both
    # axes, which is occlusion rather than crowding.
    def rect_gap(a, b)
      dx = [b["x"].to_f - (a["x"].to_f + a["w"].to_f), a["x"].to_f - (b["x"].to_f + b["w"].to_f)].max
      dy = [b["y"].to_f - (a["y"].to_f + a["h"].to_f), a["y"].to_f - (b["y"].to_f + b["h"].to_f)].max
      return nil if dx.negative? && dy.negative?

      [dx, dy].reject(&:negative?).min
    end

    # layout_rules.alignment.center_text_max_lines. Centred text gives the eye no
    # fixed left edge to return to, so every line after the third costs the
    # reader a hunt for where it starts. Only measurable once rendered, because
    # the line count depends on the box the text landed in.
    def check_centered_prose(surface, elements)
      max_lines = @rules.dig("layout_rules", "alignment", "center_text_max_lines").to_i
      return if max_lines <= 0

      offenders = elements.filter_map do |el|
        next unless el["visible"] && el["onscreen"]
        next unless el["text_align"].to_s == "center"
        # Own text only. Dividing a *container's* height by its line-height
        # counts its icon, heading, button and padding as prose: the shared
        # empty state reported 12 lines where the sentence is two. A block that
        # holds no text of its own is a layout box, and centring it is not the
        # thing this rule is about.
        next if el["text"].to_s.strip.empty?

        lh = el["line_height"].to_f
        next if lh <= 0

        lines = (el["frect"]&.dig("h").to_f / lh).round
        next if lines <= max_lines

        "#{el["key"]} (#{lines} lines)"
      end
      return if offenders.empty?

      @result.fail(
        "geometry centered_prose: #{surface.id} centres #{offenders.size} block(s) past " \
        "#{max_lines} lines — #{offenders.first(3).join('; ')} (principle=alignment)", severity: :soft
      )
    end

    def check_landmarks(surface, data)
      marks = data["landmarks"] || {}
      %w[main nav skip].each do |mark|
        next if marks[mark]

        @result.fail("geometry landmarks: #{surface.id} rendered page has no #{mark} landmark (principle=accessibility)")
      end
      h1 = data["h1_count"].to_i
      @result.fail("geometry hierarchy: #{surface.id} rendered #{h1} h1 (want 1)") if h1 > 1
      @result.fail("geometry hierarchy: #{surface.id} rendered no h1", severity: :soft) if h1.zero?
    end

    def check_overflow(surface, data)
      scroll = data["scroll_width"].to_i
      client = data["client_width"].to_i
      return if scroll <= client + 1

      offenders = Array(data["overflow"]).sort_by { |o| -o["right"].to_i }.first(3)
      names =
        if offenders.empty?
          "no single element exceeds the viewport — the spill comes from an intrinsic minimum " \
            "(a wide table, pre block, or a flex/grid track that cannot shrink)"
        else
          offenders.map { |o| "#{o["sel"]} (right=#{o["right"]})" }.join("; ")
        end
      @result.fail(
        "geometry overflow: #{surface.id} scrolls horizontally (#{scroll}px > #{client}px viewport) — #{names}",
        severity: :hard
      )
      offenders.each do |o|
        @result.autofix(app: surface.app, selector: o["sel"], kind: :overflow,
                        detail: "#{surface.id}: spills to #{o["right"]}px past #{client}px viewport")
      end
    end

    def check_fitts(surface, elements)
      targets = elements.select do |el|
        el["interactive"] && el["visible"] && !el["inline_in_text"] &&
          el.dig("rect", "w").to_i > 2 && el.dig("rect", "h").to_i > 2
      end
      return if targets.empty?

      undersized = targets.select do |el|
        [el.dig("rect", "w").to_i, el.dig("rect", "h").to_i].min + 0.01 < @min_touch
      end
      return if undersized.empty?

      undersized.group_by { |el| el["key"].to_s.sub(/\[\d+\]\z/, "") }.first(8).each do |key, group|
        el = group.first
        w = el.dig("rect", "w")
        h = el.dig("rect", "h")
        sev = critical?(el) ? :hard : :soft
        label = el["text"].to_s.empty? ? (el["aria"] || el["tag"]) : el["text"]
        @result.fail(
          "geometry touch: #{surface.id} #{key} renders #{w}×#{h} < #{@min_touch.to_i}px " \
          "(#{group.size}×, #{label.to_s.strip[0, 30].inspect}) principle=fitts_law",
          severity: sev
        )
        @result.autofix(app: surface.app, selector: key, kind: :touch,
                        detail: "#{surface.id}: rendered #{w}×#{h}, floor #{@min_touch.to_i}px") if sev == :hard
      end
    end

    def check_occlusion(surface, elements)
      blocked = elements.select { |el| el["hit"].to_s.start_with?("blocked") }
      return if blocked.empty?

      blocked.group_by { |el| el["key"].to_s.sub(/\[\d+\]\z/, "") }.first(5).each do |key, group|
        el = group.first
        sev = critical?(el) ? :hard : :soft
        @result.fail(
          "geometry occlusion: #{surface.id} #{key} centre pixel is owned by #{el["hit"].sub("blocked:", "")} " \
          "(#{group.size}× unclickable) principle=fitts_law",
          severity: sev
        )
      end
    end

    # `under_chrome` is an excuse the probe grants because scrolling moves flow
    # content out from under fixed chrome. It does not move fixed chrome. So for
    # an element whose OWN position is fixed, an occluding fixed/sticky blocker
    # is permanent and the element is unclickable for the life of the page.
    #
    # This is the class of bug that shipped twice in the same corner: the brgen
    # wordmark rendered at z-index 11 under .nav_swiper_bar at z-index 90, so
    # elementFromPoint at the mark's own centre returned the "front" nav link and
    # a tap on the brand navigated to front instead of home. Both elements are
    # correct in isolation, which is why neither design_contract nor
    # visual_contract saw it — only the composed hit test does.
    #
    # The element's own computed position is the test, not an ancestor's: these
    # apps wrap the page in a fixed .app-shell, so "has a fixed ancestor" is true
    # of every element and would indict the whole document.
    def check_chrome_occlusion(surface, elements)
      buried = elements.select do |el|
        el["position"].to_s == "fixed" && el["hit"].to_s.start_with?("under_chrome")
      end
      return if buried.empty?

      buried.group_by { |el| el["key"].to_s.sub(/\[\d+\]\z/, "") }.first(5).each do |key, group|
        el = group.first
        label = el["text"].to_s.strip.empty? ? (el["aria"] || el["tag"]) : el["text"].to_s.strip
        @result.fail(
          "geometry chrome occlusion: #{surface.id} #{key} is position:fixed " \
          "(#{label.to_s[0, 30].inspect}, z=#{el["z"] || "auto"}) and its centre pixel is owned by " \
          "#{el["hit"].sub("under_chrome:", "")} — fixed chrome cannot be scrolled out from " \
          "under a blocker, so this target is dead for the life of the page " \
          "(#{group.size}×) principle=fitts_law",
          severity: :hard
        )
        @result.autofix(app: surface.app, selector: key, kind: :occlusion,
                        detail: "#{surface.id}: fixed chrome buried by #{el["hit"].sub("under_chrome:", "")}")
      end
    end

    # The check the static parser structurally cannot do: var()/oklch/color-mix
    # arrive here already resolved by the browser, and the background is the
    # real composited stack rather than a same-file guess.
    def check_contrast(surface, elements)
      seen = {}
      elements.each do |el|
        next unless el["visible"] && !el["text"].to_s.strip.empty?

        fg = el["color"]
        bg = el["bg"]
        next unless fg && bg

        size = el["font_size"].to_f
        bold = el["font_weight"].to_s.to_i >= 700 || el["font_weight"].to_s == "bold"
        large = size >= 24 || (size >= 18.66 && bold)
        floor = large ? 3.0 : 4.5
        ratio = DesignMetrics.contrast_ratio(fg, bg)
        next unless ratio

        key = [fg, bg, large]
        next if seen[key]

        seen[key] = true
        where = el["onscreen"] == false ? " off-canvas" : ""
        if ratio < floor
          @result.fail(
            "geometry contrast: #{surface.id} #{fg} on #{bg} = #{ratio} < #{floor} " \
            "(#{size.round}px#{bold ? ' bold' : ''}, e.g.#{where} #{el["key"]}) principle=accessibility",
            severity: :hard
          )
        elsif ratio < @aaa && !large
          @result.fail(
            "geometry contrast: #{surface.id} #{fg} on #{bg} = #{ratio} < design_rules AAA #{@aaa}" \
            "#{apca_note(fg, bg, size, bold)}",
            severity: :soft
          )
        end

        check_apca(surface, el, fg, bg, size, bold)
      end
    end

    # APCA reported next to the WCAG ratio, never instead of it. The two
    # disagree in the direction that matters for a dark UI, and measured on this
    # tree they disagree completely about where the debt is: #5c586e on white is
    # 6.83 (fails AAA) but Lc 83.6 (comfortably readable), while #8a879c on
    # #17161c is 5.16 — WCAG makes it look like a near miss — and Lc 38.3, which
    # is below APCA's floor for text of any size. WCAG 2.x is symmetric and
    # perception is not: light text on a dark ground halates and reads thinner
    # than the ratio predicts.
    def apca_note(fg, bg, size, bold)
      lc = DesignMetrics.apca_lc(fg, bg)
      return "" unless lc

      " (APCA Lc #{lc.abs.round(1)}, wants #{DesignMetrics.apca_threshold(size, bold: bold).round})"
    end

    def check_apca(surface, el, fg, bg, size, bold)
      lc = DesignMetrics.apca_lc(fg, bg)
      return unless lc

      want = DesignMetrics.apca_threshold(size, bold: bold)
      return if lc.abs >= want

      key = [:apca, fg, bg, want]
      return if @apca_seen&.include?(key)

      (@apca_seen ||= {})[key] = true
      @result.fail(
        "geometry apca: #{surface.id} #{fg} on #{bg} = Lc #{lc.abs.round(1)} < #{want.round} " \
        "(#{size.round}px#{bold ? ' bold' : ''}, e.g. #{el["key"]}) principle=perceptual_contrast",
        severity: :soft
      )
    end

    def check_token_conformance(surface, data)
      colors = data["colors"] || {}
      rogue = colors.reject { |hex, _| @palette.include?(hex.to_s.downcase) }
      return if rogue.empty?

      top = rogue.sort_by { |_, count| -count }.first(4)
      @result.fail(
        "geometry tokens: #{surface.id} renders #{rogue.size} text colour(s) outside design_tokens.yml — " \
        "#{top.map { |hex, count| "#{hex}×#{count}" }.join(', ')} principle=exact_token_use",
        severity: :soft
      )
    end

    def check_rhythm(surface, data, spec = {})
      gaps = Array(data["gaps"])
      return if gaps.empty?

      off = gaps.reject { |g| on_rhythm?(g["gap"].to_i) }
      return if off.empty?

      ratio = (off.size.to_f / gaps.size * 100).round
      return if ratio < (spec["rhythm_off_max_pct"] || 25).to_i

      sample = off.group_by { |g| g["gap"] }.sort_by { |_, v| -v.size }.first(3)
      @result.fail(
        "geometry rhythm: #{surface.id} #{off.size}/#{gaps.size} rendered gaps (#{ratio}%) off the 8px scale — " \
        "#{sample.map { |px, rows| "#{px}px×#{rows.size}" }.join(', ')} principle=rhythm",
        severity: :soft
      )
    end

    def on_rhythm?(px)
      return true if @allowed_spacing.include?(px)
      return true if (px % 8).zero?
      return true if px == 4

      false
    end

    def critical?(el)
      "#{el["key"]} #{el["role"]} #{el["tag"]}".match?(CRITICAL) ||
        %w[button].include?(el["tag"]) ||
        el["role"] == "button"
    end

    # Every colour the design system actually sanctions, plus the achromatic
    # extremes every UI legitimately renders.
    # Walk the whole tree, not just one level. design_tokens.yml nests
    # vertical_accents as `messenger: { accent: "#6b7fd7", hover: "#5566c4" }`,
    # so a one-level each_value saw a Hash where it expected a hex and skipped
    # every vertical accent in the file. The channel pages were then reported as
    # painting #6b7fd7 "outside design_tokens.yml" — a colour that is declared
    # in design_tokens.yml, on the line above its own contrast measurement.
    def token_palette
      set = %w[#000000 #ffffff]
      collect_hexes(@tokens, set)
      set.compact.uniq
    end

    def collect_hexes(node, set)
      case node
      when Hash then node.each_value { |v| collect_hexes(v, set) }
      when Array then node.each { |v| collect_hexes(v, set) }
      else
        v = node.to_s.strip.downcase
        set << expand_hex(v) if v.match?(/\A#[0-9a-f]{3}([0-9a-f]{3})?\z/)
      end
    end

    def expand_hex(value)
      s = value.delete_prefix("#")
      s = s.chars.map { |c| c * 2 }.join if s.length == 3
      "##{s}"
    end
  end
end
