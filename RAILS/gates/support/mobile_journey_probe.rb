# frozen_string_literal: true

module Deploy
  class MobileJourneyProbe
    MAX_ACTIONS = 4

    ACTION_DISCOVERY = <<~JS
      (() => {
        const visible = el => {
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 0 && r.height > 0 && s.display !== "none" &&
            s.visibility !== "hidden" && s.pointerEvents !== "none";
        };
        const selector = el => el.id ? "#" + CSS.escape(el.id) :
          el.getAttribute("data-testid") ? "[data-testid='" + el.getAttribute("data-testid") + "']" : null;
        const label = el => (el.getAttribute("aria-label") || el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 48);
        const out = [];
        for (const el of document.querySelectorAll("button, summary, [aria-expanded='false'], details > summary")) {
          if (!visible(el)) continue;
          if (el.matches("button[type='submit'], button[type='reset']")) continue;
          const sel = selector(el);
          if (!sel) continue;
          out.push({kind: "toggle", selector: sel, label: label(el)});
        }
        for (const form of document.querySelectorAll("form")) {
          const field = form.querySelector("input[required], select[required], textarea[required]");
          if (!field || !visible(field)) continue;
          const sel = selector(field);
          if (sel) out.push({kind: "validation", selector: sel, label: label(field)});
        }
        const first = document.querySelector("a[href^='/'], button:not([type='submit']):not([type='reset']), input, select, textarea");
        if (first && visible(first)) {
          const sel = selector(first);
          if (sel) out.push({kind: "focus", selector: sel, label: label(first)});
        }
        return JSON.stringify(out.slice(0, #{MAX_ACTIONS}));
      })()
    JS

    ACTION = <<~JS
      (() => {
        const el = document.querySelector(%<selector>s);
        if (!el) return JSON.stringify({ok: false, reason: "missing"});
        if (%<kind>s === "validation") {
          el.focus();
          const valid = el.reportValidity();
          return JSON.stringify({ok: true, state: valid ? "valid" : "invalid", active: document.activeElement === el});
        }
        if (%<kind>s === "focus") {
          el.focus();
          return JSON.stringify({ok: true, state: "focused", active: document.activeElement === el});
        }
        el.click();
        return JSON.stringify({
          ok: true,
          state: el.getAttribute("aria-expanded") === "true" || el.parentElement?.open === true ? "expanded" : "activated"
        });
      })()
    JS

    def self.discover(cdp)
      JSON.parse(cdp.evaluate(ACTION_DISCOVERY).to_s)
    rescue StandardError
      []
    end

    def self.run(cdp, surface, dir)
      return [] unless surface.viewport == "mobile"

      baseline = cdp.evaluate("document.body ? document.body.innerText.slice(0, 4000) : ''").to_s
      states = []
      discover(cdp).each_with_index do |action, index|
        cdp.navigate(surface.url)
        result = cdp.evaluate(format(ACTION, selector: action.fetch("selector").to_json,
                                      kind: action.fetch("kind").to_json))
        sleep 0.15
        slug = surface.id.gsub(/[^a-zA-Z0-9]+/, "-").downcase
        path = File.join(dir, "journey-#{slug}-#{index}.png")
        cdp.screenshot(path, capture_beyond_viewport: true)
        after = cdp.evaluate("document.body ? document.body.innerText.slice(0, 4000) : ''").to_s
        states << action.merge("result" => JSON.parse(result.to_s), "changed" => baseline != after,
                               "screenshot" => path)
      end
      states
    rescue StandardError
      []
    end
  end
end
