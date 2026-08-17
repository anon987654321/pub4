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
        // What part of this element is actually on screen.
        //
        // getBoundingClientRect reports where an element is laid out, not where
        // it is painted. A nav link scrolled past the end of a horizontal
        // swiper has a rect beyond the scroller's edge: clipped, invisible, and
        // its "centre" lands on whatever fixed chrome happens to sit there. Six
        // surfaces reported exactly that. So intersect with every ancestor that
        // clips, and probe the middle of what survives — which is also the
        // honest point for an element only half scrolled into view.
        const visibleRect = (el) => {
          let box = el.getBoundingClientRect();
          box = { left: box.left, top: box.top, right: box.right, bottom: box.bottom };
          for (let p = el.parentElement; p; p = p.parentElement) {
            const cs = getComputedStyle(p);
            if (cs.overflowX === 'visible' && cs.overflowY === 'visible') continue;
            const c = p.getBoundingClientRect();
            box.left = Math.max(box.left, c.left);
            box.top = Math.max(box.top, c.top);
            box.right = Math.min(box.right, c.right);
            box.bottom = Math.min(box.bottom, c.bottom);
            if (box.right <= box.left || box.bottom <= box.top) return null;
          }
          box.left = Math.max(box.left, 0);
          box.top = Math.max(box.top, 0);
          box.right = Math.min(box.right, innerWidth);
          box.bottom = Math.min(box.bottom, innerHeight);
          return (box.right - box.left >= 2 && box.bottom - box.top >= 2) ? box : null;
        };

        const out = [];
        document.querySelectorAll(SELECTOR).forEach((el) => {
          const r = el.getBoundingClientRect();
          if (r.width < 2 || r.height < 2) return;

          // checkVisibility rather than this element's own computed style.
          // opacity does not inherit, so a control inside a fully transparent
          // parent computes opacity 1 and still has a rect — it is invisible and
          // unpressable, and reading only its own style reported every link in
          // a collapsed panel as occluded. This asks the browser the whole
          // question, ancestors included.
          if (!el.checkVisibility({ opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true })) return;
          // A control inside a closed dialog, a collapsed panel or an inert
          // region is not on screen to be pressed, and the browser agrees.
          if (el.closest('[hidden], [inert], [aria-hidden="true"]')) return;

          const vis = visibleRect(el);
          if (!vis) return;

          const cx = Math.round((vis.left + vis.right) / 2);
          const cy = Math.round((vis.top + vis.bottom) / 2);
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
