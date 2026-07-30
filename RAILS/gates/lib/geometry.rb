# frozen_string_literal: true

require "yaml"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/geometry_probe"
require_relative "../support/geometry_autofix"
require_relative "../support/gate_autofix"
require_relative "../support/design_metrics"

module Deploy
  # Rendered-geometry contracts: Fitts, occlusion, overflow, computed contrast,
  # token conformance, 8px rhythm — all measured in a real browser.
  #
  # This is the gate the existing layout_geometry_gate is named after but does
  # not do: that one greps `_nav.scss` for the literal string "min-height: 44px"
  # and calls the touch contract satisfied. A 44px min-height on an element that
  # is overlapped, clipped, or overridden at this breakpoint passes there and
  # fails here.
  class GeometryGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    MASTER_RULES = File.join(ROOT, "MASTER", "data", "design_rules.yml")
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
      @rules = File.file?(MASTER_RULES) ? YAML.safe_load_file(MASTER_RULES) : {}
      @tokens = File.file?(TOKENS) ? YAML.safe_load_file(TOKENS) : {}
      @min_touch = (@rules.dig("layout_rules", "touch", "target_min_px") || 44).to_f
      @aaa = (@rules.dig("typography", "accessibility", "normal_text_contrast") || 7.0).to_f
      @allowed_spacing = Array(@rules.dig("layout_rules", "grid", "allowed_spacing_px")).map(&:to_i)
      @allowed_spacing = [4, 8, 16, 24, 32, 48, 64] if @allowed_spacing.empty?
      @palette = token_palette

      unless GeometryProbe.available?
        @result.inconclusive!("geometry: no Chrome/Chromium — rendered geometry not measured (set CHROME_PATH)")
        return @result
      end

      surfaces = GeometryProbe.surfaces
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.warn("geometry: #{app} port closed — surfaces skipped")
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
      check_contrast(surface, elements)
      check_token_conformance(surface, data)
      check_rhythm(surface, data)
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
            "geometry contrast: #{surface.id} #{fg} on #{bg} = #{ratio} < design_rules AAA #{@aaa}",
            severity: :soft
          )
        end
      end
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

    def check_rhythm(surface, data)
      gaps = Array(data["gaps"])
      return if gaps.empty?

      off = gaps.reject { |g| on_rhythm?(g["gap"].to_i) }
      return if off.empty?

      ratio = (off.size.to_f / gaps.size * 100).round
      return if ratio < 25 # a few one-offs are not a rhythm failure

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
    def token_palette
      set = %w[#000000 #ffffff]
      @tokens.each_value do |dialect|
        next unless dialect.is_a?(Hash)

        dialect.each_value do |value|
          v = value.to_s.strip.downcase
          set << expand_hex(v) if v.match?(/\A#[0-9a-f]{3}([0-9a-f]{3})?\z/)
        end
      end
      set.compact.uniq
    end

    def expand_hex(value)
      s = value.delete_prefix("#")
      s = s.chars.map { |c| c * 2 }.join if s.length == 3
      "##{s}"
    end
  end
end
