# frozen_string_literal: true

require "json"

module Deploy
  class MobileJourneyProbe
    MAX_ACTIONS = 6
    MAX_NAVIGATIONS = 2

    # An interpolating heredoc, so a JavaScript regex escape is written doubled:
    # a single \b here reaches the browser as a backspace and \s as a space.
    ACTION_DISCOVERY = <<~JS
      (() => {
        const visible = el => {
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 0 && r.height > 0 && s.display !== "none" &&
            s.visibility !== "hidden" && s.pointerEvents !== "none";
        };
        const selector = el => {
          if (el.id) return "#" + CSS.escape(el.id);
          if (el.getAttribute("data-testid")) return "[data-testid='" + el.getAttribute("data-testid") + "']";
          const parts = [];
          let node = el;
          while (node && node.nodeType === 1 && node !== document.body) {
            let part = node.tagName.toLowerCase();
            let sibling = node;
            let index = 1;
            while ((sibling = sibling.previousElementSibling)) {
              if (sibling.tagName === node.tagName) index++;
            }
            part += ":nth-of-type(" + index + ")";
            parts.unshift(part);
            const candidate = parts.join(" > ");
            if (document.querySelectorAll(candidate).length === 1) return candidate;
            node = node.parentElement;
          }
          return null;
        };
        const label = el => (el.getAttribute("aria-label") || el.textContent || "").trim().replace(/\\s+/g, " ").slice(0, 48);
        const out = [];
        for (const el of document.querySelectorAll("button, summary, [aria-expanded='false'], details > summary")) {
          if (!visible(el)) continue;
          if (el.tagName === "BUTTON" && (el.getAttribute("type") || "submit").toLowerCase() !== "button") continue;
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
        const search = document.querySelector("input[type='search'], input[name*='search' i], input[placeholder*='search' i]");
        if (search && visible(search)) {
          const sel = selector(search);
          if (sel) out.push({kind: "search", selector: sel, label: label(search)});
        }
        for (const control of document.querySelectorAll("select, input[type='checkbox'], input[type='radio']")) {
          if (!visible(control) || control.disabled) continue;
          const form = control.closest("form");
          if (form && (form.getAttribute("method") || "get").toLowerCase() !== "get") continue;
          const sel = selector(control);
          if (sel) { out.push({kind: "filter", selector: sel, label: label(control)}); break; }
        }
        const origin = location.origin;
        let navigation_count = 0;
        for (const link of document.querySelectorAll("a[href]")) {
          if (navigation_count >= #{MAX_NAVIGATIONS}) break;
          if (!visible(link)) continue;
          const raw = link.getAttribute("href");
          if (!raw || raw.startsWith("#") || /^(mailto|tel|javascript):/i.test(raw)) continue;
          let url;
          try { url = new URL(raw, location.href); } catch (_) { continue; }
          if (url.origin !== origin || url.pathname === location.pathname && url.search === location.search) continue;
          if (/\\b(logout|signout|delete|destroy|remove|unsubscribe)\\b/i.test(
            [link.textContent, link.getAttribute("aria-label"), url.pathname].filter(Boolean).join(" ")
          )) continue;
          if (link.hasAttribute("data-method") || link.hasAttribute("data-turbo-method")) continue;
          const sel = selector(link);
          if (!sel) continue;
          out.push({kind: "navigation", selector: sel, label: label(link), href: url.href});
          navigation_count++;
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
        if (%<kind>s === "focus" || %<kind>s === "search") {
          el.focus();
          return JSON.stringify({ok: true, state: %<kind>s === "search" ? "search_ready" : "focused", active: document.activeElement === el});
        }
        if (%<kind>s === "filter") {
          el.focus();
          if (el.tagName === "SELECT") {
            const option = [...el.options].find(option => !option.disabled && option.value !== el.value);
            if (option) el.value = option.value;
          } else {
            el.click();
          }
          el.dispatchEvent(new Event("input", {bubbles: true}));
          el.dispatchEvent(new Event("change", {bubbles: true}));
          return JSON.stringify({ok: true, state: "filter_changed"});
        }
        if (%<kind>s === "navigation") {
          el.click();
          return JSON.stringify({ok: true, state: "navigation_started", href: el.href || el.getAttribute("href")});
        }
        el.click();
        return JSON.stringify({
          ok: true,
          state: el.getAttribute("aria-expanded") === "true" || el.parentElement?.open === true ? "expanded" : "activated"
        });
      })()
    JS

    def self.state_signature(cdp)
      JSON.parse(cdp.evaluate(<<~JS).to_s)
        (() => {
          const visible = el => {
            const r = el.getBoundingClientRect();
            return r.width > 0 && r.height > 0;
          };
          return JSON.stringify({
            url: location.href,
            active: document.activeElement?.id || document.activeElement?.tagName || "",
            text: document.body?.innerText?.slice(0, 4000) || "",
            expanded: [...document.querySelectorAll("[aria-expanded]")].filter(visible).map(el => [el.id, el.getAttribute("aria-expanded")]),
            open: [...document.querySelectorAll("details, dialog, [popover]")].filter(visible).map(el => [el.id, el.matches("dialog") ? el.open : el.hasAttribute("open") || el.matches(":popover-open")])
          });
        })()
      JS
    end

    def self.discover(cdp)
      JSON.parse(cdp.evaluate(ACTION_DISCOVERY).to_s)
    end

    def self.run(cdp, surface, dir)
      return [] unless surface.viewport == "mobile"

      states = []
      discover(cdp).each_with_index do |action, index|
        cdp.navigate(surface.url)
        sleep 0.1
        baseline = state_signature(cdp)
        result = cdp.evaluate(format(ACTION, selector: action.fetch("selector").to_json,
                                      kind: action.fetch("kind").to_json))
        sleep 0.35
        if action["kind"] == "navigation"
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
          while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            break if cdp.evaluate("document.readyState").to_s == "complete"
            sleep 0.05
          end
        end
        after = state_signature(cdp)
        slug = surface.id.gsub(/[^a-zA-Z0-9]+/, "-").downcase
        path = File.join(dir, "journey-#{slug}-#{index}.png")
        cdp.screenshot(path, capture_beyond_viewport: true)
        states << action.merge("result" => JSON.parse(result.to_s), "changed" => baseline != after,
                               "from" => surface.url, "to" => action["href"], "screenshot" => path)
        if action["kind"] == "navigation" && after["url"] != baseline["url"]
          cdp.back
          back = state_signature(cdp)
          states << action.merge("kind" => "navigation_back", "result" => {"ok" => true},
                                 "changed" => back != baseline, "from" => after["url"],
                                 "to" => surface.url)
          cdp.forward
          forward = state_signature(cdp)
          states << action.merge("kind" => "navigation_forward", "result" => {"ok" => true},
                                 "changed" => forward != after, "from" => surface.url,
                                 "to" => after["url"])
        end
      end
      states
    rescue StandardError => e
      raise "mobile journey probe failed: #{e.class}: #{e.message}"
    end
  end
end
