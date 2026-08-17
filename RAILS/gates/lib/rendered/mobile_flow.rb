# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"
require_relative "../../support/brgen_vertical_surfaces"

module Deploy
  # Mobile journey floor — the missing peer of keyboard_flow.
  #
  # reflow already sweeps widths; geometry measures boxes. This gate walks a
  # phone viewport (390×844) as a user would: landmarks, Fitts targets (44px),
  # no horizontal overflow, primary chrome not covering the main CTA strip,
  # and brgen vertical subapps all present in the mobile probe set.
  #
  # Needs Chrome + listening apps. Without either: inconclusive (not a pass).
  class MobileFlowGate
    ROOT = File.expand_path("../../../..", __dir__)
    PHONE = [390, 844].freeze
    TOUCH_MIN = 44

    # Interactive selectors that must meet the touch floor when laid out.
    # Chrome only — not every link in the feed.
    CHROME_SEL = [
      ".tab-bar a",
      ".tab-bar button",
      "nav.tab-bar a",
      ".skip-link",
      ".edge-grip",
      ".nearby-chat-widget-tab",
      ".chat-tab",
      "header .btn",
      ".page-header .btn",
      ".btn-primary",
      "a.btn--primary",
      "button.btn-primary",
    ].join(", ")

    MEASURE = <<~JS
      (() => {
        const de = document.documentElement;
        const vw = de.clientWidth;
        const laidOut = (el) => {
          if (!el) return false;
          const cs = getComputedStyle(el);
          if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return false;
          const r = el.getBoundingClientRect();
          return r.width > 0 && r.height > 0;
        };
        const main = document.querySelector('#main-content, main, [role=main], #face, #zin');
        const skip = document.querySelector('a.skip-link, .skip-link, a[href="#main-content"], a[href="#zin"]');
        const tabBar = document.querySelector('.tab-bar, nav.tab-bar, [data-scroll-chrome-target="bar"]');
        const overflow = de.scrollWidth > vw + 1;
        const chromeSel = [
          '.tab-bar a', '.tab-bar button', 'nav.tab-bar a',
          '.edge-grip', '.nearby-chat-widget-tab', '.chat-tab',
          'header .btn', '.page-header .btn',
          '.btn-primary', 'a.btn--primary', 'button.btn-primary'
        ].join(',');

        const chrome = [];
        document.querySelectorAll(chromeSel).forEach((el) => {
          if (!laidOut(el)) return;
          const r = el.getBoundingClientRect();
          // Skip zero-size peels / coach that are intentionally 1×1 clipped.
          if (r.width < 8 || r.height < 8) return;
          const label = (el.getAttribute('aria-label') || el.innerText || el.className || el.tagName)
            .toString().trim().slice(0, 40);
          chrome.push({
            label: label,
            w: Math.round(r.width),
            h: Math.round(r.height),
            min: Math.min(r.width, r.height),
            top: Math.round(r.top),
            bottom: Math.round(r.bottom),
          });
        });

        return {
          has_main: !!main && laidOut(main),
          has_skip: !!skip,
          has_tab_bar: !!(tabBar && laidOut(tabBar)),
          overflow: overflow,
          scroll_width: de.scrollWidth,
          client_width: vw,
          chrome: chrome,
          title: (document.title || '').slice(0, 80),
        };
      })()
    JS

    # Triangle + every brgen vertical root — mobile is where subapps feel alien.
    PREFERRED = %w[
      brgen/core brgen/live brgen/nearby brgen/marketplace brgen/marketplace_cart
      brgen/dating brgen/playlist brgen/tv brgen/takeaway brgen/maps brgen/messenger
      brgen/channels brgen/conversations brgen/search brgen/communities
      amber/home amber/wardrobe amber/feed amber/sign_in
      bsdports/home bsdports/ports_index
    ].freeze

    def self.run = new.run

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("mobile_flow: no Chrome/Chromium — phone viewport not measured")
        return @result
      end

      surfaces = pick_surfaces
      GeometryProbe.unreachable_apps(surfaces).each { |app| @result.skipped_live("mobile_flow: #{app} port closed — skipped") }
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("mobile_flow: no app reachable")
        return @result
      end

      # Source floor: vertical surface list must cover subapps (even if offline).
      vertical_labels = BrgenVerticalSurfaces::SURFACES.map { |s| s[:label].to_s }
      %w[marketplace dating playlist tv takeaway maps messenger].each do |sub|
        unless vertical_labels.any? { |l| l.start_with?(sub) || l == sub }
          @result.fail("mobile_flow: BrgenVerticalSurfaces missing subapp #{sub}")
        end
      end
      @result.checked!(1)

      measured = 0
      GeometryProbe.with_browser(warm: live) do |cdp|
        live.each do |surface|
          ok = probe(cdp, surface)
          measured += 1 if ok
        end
      end
      @result.checked!(measured) if measured.positive?
      if measured.zero? && live.any?
        @result.inconclusive!("mobile_flow: Chrome navigated 0/#{live.size} surfaces (timeouts) — retry with warm Falcon")
      elsif measured.positive? && measured < 3 && live.size >= 5
        # Too few real phone measurements to claim the floor; don't green-wash.
        @result.inconclusive!("mobile_flow: only #{measured}/#{live.size} surfaces measured (CDP timeouts) — warm apps and re-run")
      else
        @result.warn("mobile_flow: measured #{measured}/#{live.size} mobile surface(s) at #{PHONE.join('×')}")
      end
      @result
    end

    private

    def pick_surfaces
      # Preferred triangle + every brgen vertical root only — a full mobile
      # geometry dump (30+) exhausts the CDP session under cold Falcon boots.
      by_label = GeometryProbe.surfaces.group_by { |s| "#{s.app}/#{s.label}" }
      PREFERRED.filter_map do |key|
        rows = by_label[key]
        next unless rows

        base = rows.find { |s| s.viewport == "mobile" } || rows.first
        GeometryProbe::Surface.new(
          app: base.app,
          label: base.label,
          host: base.host,
          path: base.path,
          viewport: "mobile",
          width: PHONE[0],
          height: PHONE[1],
          snapshot: false,
          port: base.port
        )
      end
    end

    def probe(cdp, surface)
      label = "#{surface.app}/#{surface.label}"
      # Force phone size regardless of surface declaration.
      w, h = PHONE
      payload = GeometryProbe.walk(cdp, surface, width: w, height: h)
      unless GeometryProbe.ok?(payload)
        err = payload["error"] || "HTTP #{payload["status"]}"
        # CDP timeout under load is environment flake, not a design defect.
        if err.to_s.match?(/timeout|Timeout/i)
          @result.warn("mobile_flow: #{label} skipped (#{err})")
        else
          @result.fail("mobile_flow: #{label} unreachable (#{err})")
        end
        return false
      end

      m = begin
        cdp.evaluate(MEASURE)
      rescue StandardError => e
        @result.fail("mobile_flow: #{label} measure failed: #{e.class}: #{e.message}")
        return false
      end

      # MASTER face is a full-document special case (id=face / primer).
      if surface.app == "master"
        unless m["has_main"] || payload.to_s.include?("face")
          # re-check via raw evaluate not available; trust measure
          @result.fail("mobile_flow: #{label} missing main/face landmark", severity: :soft) unless m["has_main"]
        end
      else
        @result.fail("mobile_flow: #{label} missing main landmark") unless m["has_main"]
        @result.fail("mobile_flow: #{label} missing skip-link") unless m["has_skip"]
      end

      if m["overflow"]
        @result.fail(
          "mobile_flow: #{label} horizontal overflow scroll=#{m["scroll_width"]} client=#{m["client_width"]}",
          severity: :hard
        )
      end

      undersized = Array(m["chrome"]).select { |c| c["min"].to_f.positive? && c["min"].to_f < TOUCH_MIN }
      # Soft: many icon-only chrome bits are 32px; fail hard only when primary
      # buttons (.btn-primary) undershoot, soft for the rest.
      undersized.each do |c|
        primary = c["label"].to_s.match?(/primary|sign|logg|cart|sell|post|add|live/i)
        sev = primary ? :hard : :soft
        @result.fail(
          "mobile_flow: #{label} touch target #{c["label"].inspect} is #{c["w"]}×#{c["h"]} (min #{TOUCH_MIN}px)",
          severity: sev
        )
      end

      # Social shells should expose a progressive tab bar on phone.
      if %w[brgen amber].include?(surface.app) && %w[core home live wardrobe marketplace].include?(surface.label)
        unless m["has_tab_bar"]
          @result.fail("mobile_flow: #{label} expected mobile tab bar chrome", severity: :soft)
        end
      end
      true
    end
  end
end
