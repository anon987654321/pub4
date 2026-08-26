# frozen_string_literal: true

module Deploy
  class RenderedGeometryGate
    # Contrast as the browser actually painted it: every text node the walk
    # returned, scored WCAG against its real computed background and APCA
    # against the size and weight it was rendered at.
    #
    # Split out of rendered_geometry.rb when that file passed its length
    # ceiling. It is the one subject in there about colour rather than
    # geometry, and it is the rendered counterpart to the source-side checks
    # in gates/lib/research/design_metrics/contrast_checks.rb.
    #
    # A module included back into the gate, so it keeps @result and the finding
    # helpers it shares with the twenty other checks. Nothing in here builds a
    # path from __dir__ — the design_metrics split moved a css_budget.yml path
    # one directory deeper and silently ran that gate unbudgeted.
    module ContrastChecks
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
    end
  end
end
