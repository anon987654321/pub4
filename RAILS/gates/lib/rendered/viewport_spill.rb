# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/cdp_session"
require_relative "../../support/geometry_probe"
require_relative "../../../tools/crawl_support"

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
  class ViewportSpillGate
    ROOT = File.expand_path("../../../..", __dir__)
    WIDTH = 390
    HEIGHT = 844

    # Signed out, so this is the guest view of each surface. The forms behind a
    # session are the other half and are not measured here.
    SURFACES = [
      { app: "brgen", host: "brgen.no", paths: %w[/ /communities /posts/new /users/new] },
      { app: "brgen", host: "markedsplass.brgen.no", paths: %w[/ /listings /deals /shops] },
      { app: "brgen", host: "dating.brgen.no", paths: %w[/] },
      { app: "brgen", host: "tv.brgen.no", paths: %w[/ /feed /channels] },
      { app: "brgen", host: "takeaway.brgen.no", paths: %w[/] },
      { app: "brgen", host: "playlist.brgen.no", paths: %w[/] },
      { app: "brgen", host: "maps.brgen.no", paths: %w[/] },
      { app: "brgen", host: "messenger.brgen.no", paths: %w[/] },
      { app: "amber", host: "amber.brgen.no", paths: %w[/ /items] },
      { app: "bsdports", host: "bsdports.brgen.no", paths: %w[/] },
    ].freeze

    PROBE = <<~JS
      (() => {
        const vw = window.innerWidth;
        const name = el => {
          const raw = (el.className && el.className.baseVal !== undefined ? el.className.baseVal : el.className || "").toString();
          const cls = raw.trim().split(/\\s+/).filter(Boolean).slice(0, 2).join(".");
          return el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") + (cls ? "." + cls : "");
        };
        const spills = [];
        for (const el of document.querySelectorAll("body *")) {
          const cs = getComputedStyle(el);
          if (cs.display === "none" || cs.visibility === "hidden" || cs.position === "fixed") continue;
          const r = el.getBoundingClientRect();
          if (r.width === 0 || r.right <= vw + 1) continue;
          let scrolls = false;
          for (let p = el.parentElement; p; p = p.parentElement) {
            const ox = getComputedStyle(p).overflowX;
            if (ox === "auto" || ox === "scroll") { scrolls = true; break; }
          }
          if (scrolls) continue;
          const p = el.parentElement;
          if (p && p.getBoundingClientRect().right > vw + 1) continue;
          spills.push(name(el) + " reaches " + Math.round(r.right));
        }
        return JSON.stringify(Array.from(new Set(spills)).slice(0, 6));
      })()
    JS

    def self.run = new.run

    def run
      @result = GateResult.new
      return unavailable unless CdpSession.available?

      ports = GeometryProbe.app_ports(root: ROOT)
      CdpSession.open(host_map: host_map(ports), timeout: 45) do |cdp|
        cdp.viewport(WIDTH, HEIGHT, mobile: true)
        surfaces.each { |surface| measure(cdp, surface, ports) }
      end
      @result
    rescue CdpSession::Error => e
      # A browser that will not start measured nothing, and a gate that reports
      # nothing measured as a pass is the failure this file exists to prevent.
      @result.inconclusive!("viewport_spill: #{e.class}: #{e.message}")
      @result
    end

    private

    # Through the class, so a subclass pointing this at one page does not
    # silently measure the parent's whole list.
    def surfaces = self.class::SURFACES

    def unavailable
      @result.inconclusive!("viewport_spill: no Chrome, so no surface was measured at #{WIDTH}px")
      @result
    end

    def host_map(ports)
      surfaces.filter_map do |surface|
        port = ports[surface[:app]]
        [surface[:host], "127.0.0.1:#{port}"] if port
      end.to_h
    end

    def measure(cdp, surface, ports)
      port = ports[surface[:app]]
      unless port && CrawlSupport.port_open?("127.0.0.1", port)
        @result.skipped_live("viewport_spill: #{surface[:host]} skipped (#{surface[:app]} not listening)")
        return
      end

      surface[:paths].each do |path|
        cdp.navigate("http://#{surface[:host]}#{path}", settle: 0.8)
        next unless cdp.status.to_i == 200

        spills = JSON.parse(cdp.evaluate(PROBE).to_s)
        if spills.empty?
          @result.checked!
        else
          @result.fail("viewport_spill: #{surface[:host]}#{path} at #{WIDTH}px — #{spills.join('; ')}")
        end
      end
    end
  end
end
