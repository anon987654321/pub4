# frozen_string_literal: true

require "json"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/cdp_session"
require_relative "../../support/geometry_probe"
require_relative "../../../tools/crawl_support"

module Deploy
  # The text contrast of every control that paints its own background.
  #
  # This exists because axe runs on three pages. brgen's PublicNavigationTest
  # and bsdports' both visit root and stop, amber's does the same, and the seven
  # brgen verticals are each a different host — so nothing measured them, and on
  # 2026-09-11 that is where every failure was. takeaway painted every .btn with
  # a gradient from one competitor's red into another's magenta, measuring 3.43
  # and 2.15 against its own ink; tv and maps each overrode the accent's
  # background and left the shared rule's --accent-ink behind, at 3.60 and 3.34;
  # amber's wardrobe swatch put --text on a charcoal garment at 1.21.
  #
  # Scope is deliberately narrow. Only controls with an opaque background of
  # their own are measured, because only there is the foreground/background pair
  # unambiguous. Text over an image, a gradient or a translucent fill needs the
  # whole ancestor stack composited, which is axe's job — and a gate that
  # guesses at a background reports numbers nobody can act on, which is worse
  # than not reporting.
  class AccentContrastGate
    ROOT = File.expand_path("../../../..", __dir__)

    # WCAG 2.1 1.4.3: 3:1 for large text, 4.5:1 otherwise, where large is 24px
    # or 18.66px when bold. The floor is decided per element in the browser,
    # because it depends on the computed size and weight rather than on the
    # selector.
    PROBE = <<~JS
      (() => {
        const rgb = (s) => {
          const m = s.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/);
          return m ? { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] } : null;
        };
        const lin = (c) => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
        const lum = (c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
        const ratio = (a, b) => {
          const x = lum(a), y = lum(b);
          return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
        };

        const bad = [];
        document.querySelectorAll("a, button, input[type=submit], .btn, [role=button]").forEach((el) => {
          const r = el.getBoundingClientRect();
          if (r.width === 0 || r.height === 0) return;

          const style = getComputedStyle(el);
          if (style.visibility === "hidden" || style.display === "none") return;
          if (style.backgroundImage !== "none") return;

          const bg = rgb(style.backgroundColor);
          const fg = rgb(style.color);
          if (!bg || !fg || bg.a < 0.95) return;

          const px = parseFloat(style.fontSize);
          const bold = parseInt(style.fontWeight, 10) >= 700;
          const floor = (px >= 24 || (bold && px >= 18.66)) ? 3 : 4.5;
          const got = ratio(fg, bg);
          if (got >= floor) return;

          const raw = (el.className && el.className.baseVal !== undefined ? el.className.baseVal : el.className || "").toString();
          const cls = raw.trim().split(/\\s+/).filter(Boolean).slice(0, 2).join(".");
          bad.push({
            sel: el.tagName.toLowerCase() + (cls ? "." + cls : ""),
            text: (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 24),
            got: Math.round(got * 100) / 100,
            floor: floor,
            px: Math.round(px * 10) / 10
          });
        });

        // One row per selector and ratio. A grid of twenty identical cards is
        // one defect, and listing it twenty times buries the next one.
        const seen = new Set();
        return JSON.stringify(bad.filter((b) => {
          const key = b.sel + ":" + b.got;
          if (seen.has(key)) return false;
          seen.add(key);
          return true;
        }).slice(0, 12));
      })()
    JS

    def self.run = new.run

    def run
      @result = GateResult.new
      return unavailable unless CdpSession.available?

      CdpSession.open(host_map: GeometryProbe.host_map(root: ROOT), timeout: 60) do |cdp|
        surfaces.each { |surface| measure(cdp, surface) }
      end
      @result
    rescue CdpSession::Error => e
      # A browser that will not start measured nothing, and a gate reporting
      # nothing measured as a pass is the failure GateResult exists to prevent.
      @result.inconclusive!("accent_contrast: #{e.class}: #{e.message}")
      @result
    end

    private

    # From the declared fleet, not a list of its own. A second surface inventory
    # is the drift this repo keeps paying for, and the marketplace subdomain is
    # localised per city — markedsplass in Bergen, marketplace in Los Angeles —
    # so there is no single name to hardcode even if a list were wanted.
    #
    # One viewport per surface rather than the full sweep. The floor moves with
    # computed font size, so a narrow viewport can in principle change a
    # verdict; what it cannot change is the colour pair, which is what this
    # measures. The first declared viewport per surface is the cheap 90%, and
    # GATE_SURFACES narrows a run while iterating.
    def surfaces
      GeometryProbe.filter(GeometryProbe.surfaces)
                   .group_by { |surface| [surface.app, surface.label] }
                   .map { |_key, group| group.first }
    end

    def unavailable
      @result.inconclusive!("accent_contrast: no Chrome, so no surface was measured")
      @result
    end

    def measure(cdp, surface)
      name = "#{surface.app}/#{surface.label}"
      unless surface.port && CrawlSupport.port_open?("127.0.0.1", surface.port)
        @result.skipped_live("accent_contrast: #{name} skipped (#{surface.app} not listening)")
        return
      end

      cdp.viewport(surface.width, surface.height)
      cdp.navigate(url_for(surface), settle: 0.8)
      return unless cdp.status.to_i == 200

      bad = JSON.parse(cdp.evaluate(PROBE).to_s)
      if bad.empty?
        @result.checked!
      else
        bad.each do |finding|
          @result.fail(format("accent_contrast: %s %s %s is %.2f, needs %s at %spx",
                              name, finding["sel"], finding["text"].inspect,
                              finding["got"], finding["floor"], finding["px"]))
        end
      end
    end

    def url_for(surface)
      host = surface.host || "127.0.0.1"
      "http://#{host}:#{surface.port}#{surface.path}"
    end
  end
end
