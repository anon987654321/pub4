# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"
require_relative "../../support/geometry_autofix"
require_relative "../../support/gate_autofix"

module Deploy
  # Width sweep instead of three fixed viewports.
  #
  # Responsive bugs live *between* breakpoints — a grid that fits at 390 and at
  # 1440 and spills at 480. Testing three widths structurally cannot see them.
  # This sweeps the declared width list collecting only cheap scalars per step,
  # and asserts two things:
  #
  #   1. No horizontal overflow at any width, with 320px as the WCAG 1.4.10 floor.
  #   2. Layout changes happen only at declared breakpoints. The set of widths
  #      where the column count or nav variant changes is a "breakpoint
  #      fingerprint" — small, stable, and committable. An unplanned transition
  #      appearing mid-range is a regression even when nothing looks broken.
  class ReflowGate
    ROOT = File.expand_path("../../../..", __dir__)

    # Sampled at each width — kept tiny so a 16-step sweep stays fast.
    SCALARS = <<~JS
      (() => {
        const de = document.documentElement;
        const vw = de.clientWidth;
        const offenders = [];
        const els = document.querySelectorAll('body *');
        for (let i = 0; i < els.length && offenders.length < 5; i++) {
          const el = els[i];
          const cs = getComputedStyle(el);
          if (cs.display === 'none' || cs.visibility === 'hidden') continue;
          const r = el.getBoundingClientRect();
          if (r.width > 4 && r.right > vw + 1) {
            const cls = String(el.className || '').split(' ').filter(Boolean).slice(0, 2).join('.');
            offenders.push(el.tagName.toLowerCase() + (cls ? '.' + cls : '') + '@' + Math.round(r.right));
          }
        }
        // Column count by geometry, not by gridTemplateColumns: the containers
        // here are flex and swiper-based, so the CSS property is 'none' at every
        // width and a fingerprint built on it would report "no transitions"
        // while seeing nothing. Grouping the first row of cards by their top
        // edge works for grid, flex wrap and float alike.
        let columns = 0;
        const grid = document.querySelector('.deal-grid, .feed, .card-grid, main ul, main > div');
        if (grid) {
          const kids = Array.from(grid.children).filter((k) => {
            const c = getComputedStyle(k);
            if (c.display === 'none' || c.position === 'absolute' || c.position === 'fixed') return false;
            const r = k.getBoundingClientRect();
            return r.width > 0 && r.height > 0;
          });
          if (kids.length) {
            const firstTop = Math.round(kids[0].getBoundingClientRect().top);
            columns = kids.filter((k) => Math.abs(Math.round(k.getBoundingClientRect().top) - firstTop) <= 4).length;
          }
        }

        const tabBar = document.querySelector('.tab-bar, nav.tab-bar');
        const sidebar = document.querySelector('aside.sidebar, .sidebar');
        const laidOut = (el) => {
          if (!el) return false;
          const cs = getComputedStyle(el);
          return !(cs.display === 'none' || cs.visibility === 'hidden');
        };
        // "On canvas" is the distinction that matters for an off-canvas drawer:
        // it is laid out at every width and only its position changes.
        const onCanvas = (el) => {
          if (!laidOut(el)) return false;
          const r = el.getBoundingClientRect();
          return r.width > 0 && r.right > 0 && r.left < de.clientWidth;
        };
        const main = document.querySelector('#main-content, main, [role=main]');
        return {
          scroll_width: de.scrollWidth,
          client_width: de.clientWidth,
          columns: columns,
          tab_bar: laidOut(tabBar),
          sidebar: onCanvas(sidebar),
          main_width: main ? Math.round(main.getBoundingClientRect().width) : 0,
          offenders: offenders
        };
      })()
    JS

    def self.run
      return run_once unless GateAutofix.enabled?

      GateAutofix.remeasure_loop(
        measure: -> { run_once },
        apply: ->(result) { GeometryAutofix.apply(result.autofix_findings, dry: GateAutofix.dry_run?) },
        label: "reflow_autofix"
      )
    end

    def self.run_once = new.run

    class Result < GateResult
      def autofix_findings = (@autofix_findings ||= [])

      def autofix(app:, selector:, kind:, detail: nil)
        autofix_findings << { app: app, selector: selector, kind: kind, detail: detail }
      end
    end

    def run
      @result = Result.new
      unless GeometryProbe.available?
        @result.inconclusive!("reflow: no Chrome/Chromium — width sweep not run")
        return @result
      end

      widths = GeometryProbe.reflow_widths
      if widths.empty?
        @result.fail("reflow: geometry_surfaces.yml declares no reflow_widths")
        return @result
      end

      surfaces = pick_surfaces
      GeometryProbe.unreachable_apps(surfaces).each { |app| @result.skipped_live("reflow: #{app} port closed — skipped") }
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("reflow: no app reachable")
        return @result
      end

      GeometryProbe.with_browser do |cdp|
        live.each { |surface| sweep(cdp, surface, widths) }
      end
      # Counted per surface, so one surface that could not be measured does not
      # make the ones that were count for nothing.
      @result.checked!(live.size)
      @result.warn("reflow: swept #{widths.length} widths (#{widths.first}–#{widths.last}px) × #{live.size} surface(s)")
      @result
    end

    private

    def pick_surfaces
      GeometryProbe.surfaces
                   .select { |s| s.viewport == "mobile" }
                   .uniq { |s| "#{s.app}/#{s.label}" }
                   .group_by(&:app)
                   .flat_map { |_app, rows| rows.first(3) }
    end

    def sweep(cdp, surface, widths)
      samples = {}
      widths.each do |width|
        begin
          cdp.viewport(width, 900, mobile: width < 500)
          cdp.navigate(surface.url, settle: 0.1)
          GeometryProbe.wait_for_fonts(cdp, timeout: 2)
          samples[width] = cdp.evaluate(SCALARS)
        rescue CdpSession::Error => e
          @result.warn("reflow: #{surface.app}/#{surface.label} @#{width}px — #{e.class.name.split("::").last}")
          next
        end
      end
      return if samples.empty?

      check_overflow(surface, samples)
      check_breakpoints(surface, samples)
    end

    def check_overflow(surface, samples)
      spills = samples.select { |_w, s| s["scroll_width"].to_i > s["client_width"].to_i + 1 }
      return if spills.empty?

      widths = spills.keys
      # 320px is the WCAG 1.4.10 reflow floor; spilling there is a hard failure
      # regardless of what the design intends above it.
      severity = widths.min <= 360 ? :hard : :soft
      worst = spills.max_by { |_w, s| s["scroll_width"].to_i - s["client_width"].to_i }
      offenders = Array(worst[1]["offenders"]).first(3)
      @result.fail(
        "reflow overflow: #{surface.app}/#{surface.label} scrolls horizontally at #{widths.join(', ')}px " \
        "(worst #{worst[0]}px: #{worst[1]["scroll_width"]} > #{worst[1]["client_width"]}#{offenders.empty? ? "" : " — #{offenders.join(', ')}"}) " \
        "principle=accessibility",
        severity: severity
      )
      offenders.each do |o|
        selector = o.split("@").first
        next if selector.to_s.match?(/\A[a-z]+\z/)

        @result.autofix(app: surface.app, selector: selector, kind: :overflow,
                        detail: "#{surface.app}/#{surface.label}: spills at #{worst[0]}px viewport")
      end
    end

    # The fingerprint: widths at which a layout property flips. Reported as a
    # warning so it lands in the run output and can be eyeballed against the
    # stylesheet's declared media queries; promoted to a soft failure when a
    # surface transitions more than a design system plausibly declares.
    def check_breakpoints(surface, samples)
      ordered = samples.sort_by(&:first)
      transitions = []
      ordered.each_cons(2) do |(w1, a), (w2, b)|
        changed = %w[columns tab_bar sidebar].select { |k| a[k] != b[k] }
        next if changed.empty?

        transitions << "#{w1}→#{w2}px: #{changed.map { |k| "#{k} #{a[k]}→#{b[k]}" }.join(', ')}"
      end

      # main_width is continuous, so it is not a transition — but reporting its
      # range tells you whether the surface actually adapts or merely stretches.
      widths = ordered.map { |(_w, s)| s["main_width"].to_i }.reject(&:zero?)
      span = widths.empty? ? "" : " [main #{widths.min}→#{widths.max}px]"

      if transitions.empty?
        @result.warn(
          "reflow fingerprint: #{surface.app}/#{surface.label} — no discrete layout transition across " \
          "#{ordered.first[0]}–#{ordered.last[0]}px#{span}; the surface scales continuously rather than " \
          "switching at breakpoints"
        )
        return
      end

      @result.warn("reflow fingerprint: #{surface.app}/#{surface.label}#{span} — #{transitions.join(' | ')}")
      return if transitions.size <= 4

      @result.fail(
        "reflow breakpoints: #{surface.app}/#{surface.label} changes layout at #{transitions.size} points " \
        "across #{ordered.first[0]}–#{ordered.last[0]}px — more transitions than a declared breakpoint set " \
        "(likely content-driven reflow rather than designed breakpoints)",
        severity: :soft
      )
    end
  end
end
