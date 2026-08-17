# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/geometry_probe"

module Deploy
  # Does a click on this control reach this control?
  #
  # Rect intersection is the obvious implementation and the wrong one: this
  # design deliberately stacks things. The nav bar is fixed over the scrolling
  # feed, the chat widget sits above the corner of everything, the composer is a
  # modal over the page. Overlap is the design; a control that cannot be pressed
  # is the defect, and those are different questions.
  #
  # So this asks the browser the question a finger asks. Take each control's
  # centre point, call elementFromPoint, and see what answers. The browser
  # accounts for stacking contexts, transforms, clip paths and pointer-events on
  # its own — a decorative overlay set to pointer-events: none never answers,
  # which is exactly right and is why a geometric check would have flagged it.
  #
  # An answer that is the control, inside it, or containing it is a hit. Anything
  # else means the press lands on something the visitor did not aim at.
  class OcclusionGate
    ROOT = File.expand_path("../../..", __dir__)

    PROBE = <<~JS
      (() => {
        const SELECTOR = 'a[href], button, input:not([type=hidden]), select, textarea,' +
          ' summary, [role="button"], [role="link"], [role="tab"], [role="menuitem"]';
        const name = (el) => {
          if (!el) return 'nothing';
          const cls = String(el.className || '').split(/\\s+/).filter(Boolean).slice(0, 2).join('.');
          return el.tagName.toLowerCase() + (el.id ? '#' + el.id : (cls ? '.' + cls : ''));
        };
        const out = [];
        document.querySelectorAll(SELECTOR).forEach((el) => {
          const r = el.getBoundingClientRect();
          if (r.width < 2 || r.height < 2) return;

          const cs = getComputedStyle(el);
          if (cs.visibility === 'hidden' || cs.display === 'none') return;
          if (parseFloat(cs.opacity) === 0) return;
          // A control inside a closed dialog, a collapsed panel or an inert
          // region is not on screen to be pressed, and the browser agrees.
          if (el.closest('[hidden], [inert], [aria-hidden="true"]')) return;

          const cx = Math.round(r.left + r.width / 2);
          const cy = Math.round(r.top + r.height / 2);
          // Off-viewport centres cannot be probed; elementFromPoint is defined
          // in terms of the viewport, not the document.
          if (cx < 0 || cy < 0 || cx >= innerWidth || cy >= innerHeight) return;

          const hit = document.elementFromPoint(cx, cy);
          if (!hit) return;
          if (hit === el || el.contains(hit) || hit.contains(el)) return;

          out.push({
            control: name(el),
            label: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().slice(0, 40),
            covered_by: name(hit),
            at: [cx, cy],
            size: [Math.round(r.width), Math.round(r.height)]
          });
        });
        return out;
      })()
    JS

    def self.run = new.run

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("occlusion: no Chrome/Chromium — nothing was pressed")
        return @result
      end

      surfaces = GeometryProbe.surfaces
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("occlusion: #{app} port closed — skipped")
      end
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("occlusion: no app reachable")
        return @result
      end

      GeometryProbe.with_browser { |cdp| live.each { |surface| probe(cdp, surface) } }
      @result.checked!(live.size)
      @result
    end

    private

    def probe(cdp, surface)
      label = "#{surface.app}/#{surface.label}/#{surface.viewport}"
      payload = GeometryProbe.walk(cdp, surface)
      unless GeometryProbe.ok?(payload)
        error = payload["error"] || "HTTP #{payload["status"]}"
        # A navigation timeout is the probe having a bad minute, not the page
        # having a defect; the other gates draw the same line.
        if error.to_s.match?(/timeout/i)
          @result.warn("occlusion: #{label} skipped (#{error})")
        else
          @result.fail("occlusion: #{label} unreachable (#{error})")
        end
        return
      end

      Array(cdp.evaluate(PROBE)).each do |hit|
        @result.fail(
          "occlusion: #{label} — #{hit["control"]}#{" (#{hit['label']})" unless hit["label"].to_s.empty?} " \
          "is covered by #{hit["covered_by"]} at #{hit["at"].join(",")}; a press there misses it"
        )
      end
    end
  end
end
