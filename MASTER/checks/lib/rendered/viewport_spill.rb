# frozen_string_literal: true

require "json"
require_relative "../../support/check_result"
require_relative "../../../lib/gap"
require_relative "../../support/cdp_session"
require_relative "../../support/geometry_probe"
require_relative "../../support/crawl_support"

module Deploy
  # Whether anything hangs off the right edge of a phone.
  #
  # Six surfaces did, each for a different reason and none of them visible to a
  # source read: a percentage max-width that does not count the element's own
  # margins, a fieldset whose min-width is min-content, an untemplated grid
  # column handing a file input its intrinsic width, a full bleed cancelling a
  # pad the page does not apply, and a flex item sized to its content. What they
  # share is the symptom — a strip of the page a phone cannot reach — and that
  # is measurable, so it belongs here rather than in a review.
  #
  # An element past the edge is only a finding when nothing above it scrolls
  # sideways. A horizontal chip rail is meant to run past the viewport; that is
  # what the scroller is for.
  class ViewportSpillCheck
    ROOT = File.expand_path("../../../..", __dir__)

    WIDTH = 390
    WIDTHS = [320, WIDTH].freeze
    HEIGHT = 844

    # Signed out, so this is the guest view of each surface. The forms behind a
    # session are the other half and are not measured here.
    SURFACES = [
      { app: "brgen", host: "brgen.no", paths: %w[/ /communities /posts/new /users/new] },
      { app: "brgen", host: "markedsplass.brgen.no", paths: %w[/ /listings /deals /shops] },
      { app: "brgen", host: "dating.brgen.no", paths: %w[/] },
      { app: "brgen", host: "tv.brgen.no", paths: %w[/ /feed /channels] },
      { app: "brgen", host: "takeaway.brgen.no", paths: %w[/] },
      { app: "brgen", host: "radio.brgen.no", paths: %w[/] },
      { app: "brgen", host: "maps.brgen.no", paths: %w[/] },
      { app: "brgen", host: "messenger.brgen.no", paths: %w[/] },
      { app: "amber", host: "amberapp.art", paths: %w[/ /items] },
      { app: "bsdports", host: "bsdports.org", paths: %w[/] },
    ].freeze

    PROBE = <<~JS
      (() => {
        const vw = window.innerWidth;
        const name = el => {
          const raw = (el.className && el.className.baseVal !== undefined ? el.className.baseVal : el.className || "").toString();
          const cls = raw.trim().split(/\\s+/).filter(Boolean).slice(0, 2).join(".");
          return el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") + (cls ? "." + cls : "");
        };
        // html and body are not ancestors for this question. Every other element
        // that clips is a component whose author decided what is on screen; the
        // root clipping is the page-level "kill the horizontal scrollbar" hack,
        // and it conceals unreachable content rather than intending it. brgen
        // sets `html, body { overflow: hidden }` for its edge-swipe shell, so
        // treating the root like any other scroller made this check blind on all
        // sixteen of its brgen surfaces: every one reported clean because nothing
        // could ever be reported at all.
        const root = new Set([document.documentElement, document.body]);
        const spills = [];
        for (const el of document.querySelectorAll("body *")) {
          const cs = getComputedStyle(el);
          if (cs.display === "none" || cs.visibility === "hidden" || cs.position === "fixed") continue;
          const r = el.getBoundingClientRect();
          if (r.width === 0 || r.right <= vw + 1) continue;
          let scrolls = false;
          for (let p = el.parentElement; p; p = p.parentElement) {
            if (root.has(p)) continue;
            const ox = getComputedStyle(p).overflowX;
            // hidden and clip belong here for the same reason auto and scroll do:
            // the ancestor decides what is on screen, and content it clips cannot
            // widen the page. Without them a CSS marquee -- a max-content track
            // inside an overflow:hidden viewport -- reported as a spill at every
            // width while document.scrollWidth stayed exactly the viewport width.
            if (ox === "auto" || ox === "scroll" || ox === "hidden" || ox === "clip") { scrolls = true; break; }
          }
          if (scrolls) continue;
          const p = el.parentElement;
          if (p && !root.has(p) && p.getBoundingClientRect().right > vw + 1) continue;
          spills.push(name(el) + " reaches " + Math.round(r.right));
        }
        return JSON.stringify(Array.from(new Set(spills)).slice(0, 6));
      })()
    JS

    def self.run = new.run

    def run
      @result = CheckResult.new
      return unavailable unless CdpSession.available?

      ports = GeometryProbe.app_ports(root: ROOT)
      CdpSession.open(host_map: host_map(ports), timeout: 45) do |cdp|
        WIDTHS.each do |width|
          cdp.viewport(width, HEIGHT, mobile: true)
          surfaces.each { |surface| measure(cdp, surface, ports, width:) }
        end
      end

      @result
    rescue CdpSession::Error => e
      # A browser that will not start measured nothing, and a check that reports
      # nothing measured as a pass is the failure this file exists to prevent.
      @result.inconclusive!("viewport_spill: #{e.class}: #{e.message}")
      @result
    end

    private

    # Through the class, so a subclass pointing this at one page does not
    # silently measure the parent's whole list.
    def surfaces = self.class::SURFACES

    def unavailable
      @result.inconclusive!("viewport_spill: no Chrome, so no surface was measured at #{WIDTHS.join("/")}px", gap: Master::Gap::NO_BROWSER)
      @result
    end

    def host_map(ports)
      surfaces.filter_map do |surface|
        port = ports[surface[:app]]
        [surface[:host], "127.0.0.1:#{port}"] if port
      end.to_h
    end

    def measure(cdp, surface, ports, width:)
      port = ports[surface[:app]]
      unless port && CrawlSupport.port_open?("127.0.0.1", port)
        @result.skipped_live("viewport_spill: #{surface[:host]} skipped (#{surface[:app]} not listening)")
        return
      end

      surface[:paths].each do |path|
        cdp.navigate("http://#{surface[:host]}#{path}", settle: 0.8)
        status = cdp.status.to_i
        unless status == 200
          @result.fail("viewport_spill: #{surface[:host]}#{path} returned HTTP #{status} — viewport overflow was not measured at #{width}px")
          next
        end

        spills = JSON.parse(cdp.evaluate(PROBE).to_s)

        if spills.empty?
          @result.checked!
        else
          @result.fail("viewport_spill: #{surface[:host]}#{path} at #{width}px — #{spills.join('; ')}")
        end
      end
    end
  end
end
