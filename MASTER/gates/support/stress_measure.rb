# frozen_string_literal: true

require_relative "stress_scripts"

module Deploy
  # What a stressed layout is measured for: horizontal overflow, text cut off
  # by a clipping ancestor, truncation too short to read, text spilling out of
  # its container, and text or controls laid on top of each other. One script,
  # one JSON answer; Ruby decides which findings are new against the resting
  # page.
  module StressMeasure
    CAP = 12

    MEASURE_JS = <<~'JS'.sub("__PATH__") { StressScripts::PATH_JS }.freeze
      (() => {
        __PATH__
        const vw = document.documentElement.clientWidth;
        const found = [];
        const add = (kind, el, detail, extra) => found.push(Object.assign({ kind, selector: path(el), detail }, extra || {}));
        const all = Array.from(document.body.querySelectorAll("*")).slice(0, 3000);
        const styles = new Map();
        const st = (el) => { if (!styles.has(el)) styles.set(el, getComputedStyle(el)); return styles.get(el); };
        const shown = (el) => {
          const r = el.getBoundingClientRect(); const s = st(el);
          return r.width > 1 && r.height > 1 && s.display !== "none" && s.visibility !== "hidden" && s.opacity !== "0";
        };
        const ownText = (el) => Array.from(el.childNodes).some((n) => n.nodeType === 3 && n.data.trim().length > 1);
        const textRect = (el) => {
          const range = document.createRange(); range.selectNodeContents(el);
          return range.getBoundingClientRect();
        };
        const hides = (v) => v === "hidden" || v === "clip";
        const texty = all.filter((el) => shown(el) && ownText(el) && !el.closest("script,style,svg,[hidden]"));

        // Horizontal overflow of the page, with the boxes that cause it.
        const scrollW = document.documentElement.scrollWidth;
        if (scrollW > vw + 1) {
          const culprits = all.filter((el) => {
            if (!shown(el) || ["fixed"].includes(st(el).position)) return false;
            if (el.getBoundingClientRect().right <= vw + 1) return false;
            for (let a = el.parentElement; a && a !== document.body; a = a.parentElement) {
              const s = st(a);
              if (s.overflowX !== "visible" && a.getBoundingClientRect().right <= vw + 1) return false;
            }
            return true;
          }).slice(0, 4);
          if (culprits.length === 0) found.push({ kind: "horizontal_overflow", selector: "html", detail: "page scrolls " + (scrollW - vw) + "px sideways" });
          culprits.forEach((el) => add("horizontal_overflow", el, "right edge " + Math.round(el.getBoundingClientRect().right) + "px, viewport " + vw + "px"));
        }

        // Truncation: an ellipsis or line clamp that leaves too little to read.
        for (const el of texty) {
          const s = st(el);
          const ell = s.textOverflow === "ellipsis" && hides(s.overflowX);
          const clamp = s.webkitLineClamp && s.webkitLineClamp !== "none";
          const cut = ell ? el.scrollWidth - el.clientWidth : clamp ? el.scrollHeight - el.clientHeight : 0;
          if (cut <= 1) continue;
          const kept = ell ? el.clientWidth / el.scrollWidth : el.clientHeight / el.scrollHeight;
          if (el.clientWidth < 48 || kept < 0.35) add("unreadable_truncation", el, Math.round(kept * 100) + "% of the text visible, " + el.clientWidth + "px wide");
        }

        // Clipping: text still partly visible inside an ancestor that cuts it.
        for (const el of texty) {
          const t = textRect(el);
          for (let a = el; a && a !== document.body; a = a.parentElement) {
            const s = st(a); const r = a.getBoundingClientRect();
            if (a === el && s.textOverflow === "ellipsis") break;
            const x = hides(s.overflowX) && (t.right > r.right + 2 || t.left < r.left - 2);
            const y = hides(s.overflowY) && t.bottom > r.bottom + 2 && r.height > 0;
            const inside = t.left < r.right && t.right > r.left && t.top < r.bottom && t.bottom > r.top;
            if ((x || y) && inside && r.width > 8) { add("clipped_text", el, "cut by " + path(a) + " (" + (x ? "sideways" : "downward") + ")"); break; }
          }
        }

        // Escape: text leaves a styled container that does not clip it.
        for (const el of texty) {
          const s = st(el);
          if (["absolute", "fixed"].includes(s.position)) continue;
          const t = textRect(el);
          for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
            const ps = st(p);
            if (/^(inline|contents)/.test(ps.display)) continue;
            const r = p.getBoundingClientRect();
            const boxed = ps.backgroundColor !== "rgba(0, 0, 0, 0)" || parseFloat(ps.borderTopWidth) > 0 || parseFloat(ps.borderLeftWidth) > 0 || ps.boxShadow !== "none";
            if (boxed && ps.overflowX === "visible" && (t.right > r.right + 2 || t.left < r.left - 2) && r.width > 8) {
              add("text_escapes_container", el, "text spans " + Math.round(t.left) + "-" + Math.round(t.right) + "px, container " + Math.round(r.left) + "-" + Math.round(r.right) + "px", { container: path(p) });
            }
            break;
          }
        }

        // Overlap: static-flow text and controls that share pixels.
        const boxes = all.filter((el) => shown(el) && (ownText(el) || /^(A|BUTTON|INPUT|SELECT|TEXTAREA)$/.test(el.tagName)) &&
          !["absolute", "fixed", "sticky"].includes(st(el).position) && !el.closest("svg,[hidden]")).slice(0, 500)
          .map((el) => ({ el, r: ownText(el) ? textRect(el) : el.getBoundingClientRect() }));
        for (let i = 0; i < boxes.length; i++) {
          for (let j = i + 1; j < boxes.length; j++) {
            const a = boxes[i], b = boxes[j];
            if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
            const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
            const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
            if (w < 4 || h < 4) continue;
            const small = Math.min(a.r.width * a.r.height, b.r.width * b.r.height);
            if (w * h / small > 0.25) add("overlap", a.el, "overlaps " + path(b.el) + " by " + Math.round(w) + "x" + Math.round(h) + "px", { other: path(b.el) });
          }
        }
        return { viewport_width: vw, scroll_width: scrollW, scroll_height: document.documentElement.scrollHeight, findings: found };
      })()
    JS

    module_function

    # Clones of one card share a finding, so positions are not part of identity.
    def identity(finding) = [finding["kind"], finding["selector"].to_s.gsub(/:nth-of-type\(\d+\)/, "")]

    # Findings the stressed page shows that the resting page did not, one per
    # identity with the count of its look-alikes, as { "kind", "selector", "detail", "similar" }.
    def new_findings(measured, baseline)
      known = Array(baseline && baseline["findings"]).map { |f| identity(f) }
      fresh = Array(measured && measured["findings"]).reject { |f| known.include?(identity(f)) }
      fresh.group_by { |f| identity(f) }.values.first(CAP).map { |group| group.first.merge("similar" => group.size - 1) }
    end
  end
end
