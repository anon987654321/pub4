# frozen_string_literal: true

require_relative "cdp_session"

module Deploy
  # The tab sequence the browser actually walks. DOM order is only the default:
  # positive tabindex, roving tabindex, shadow hosts and reordered flex/grid
  # items all move focus somewhere the markup does not say. Tab is pressed
  # through CDP and each stop's box is read back, so a consumer compares what
  # the keyboard user is given with what the eye reads.
  module FocusOrderProbe
    LIMIT = 60

    ACTIVE_JS = <<~JS.freeze
      (() => {
        const el = document.activeElement;
        if (!el || el === document.body || el === document.documentElement) return null;
        const r = el.getBoundingClientRect();
        const cls = [...el.classList].slice(0, 2).map(c => '.' + c).join('');
        return {
          key: el.__gpKey || null,
          sel: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + cls,
          x: Math.round((r.left + scrollX) * 10) / 10, y: Math.round((r.top + scrollY) * 10) / 10,
          w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10,
          tabindex: el.getAttribute('tabindex'), position: getComputedStyle(el).position
        };
      })()
    JS

    RESET_JS = "(() => { if (document.activeElement) document.activeElement.blur(); scrollTo(0, 0); " \
               "getSelection().removeAllRanges(); return getComputedStyle(document.documentElement).direction; })()"

    module_function

    # {"tab_order" => [stops], "text_dir" => "ltr"|"rtl", "tab_order_status" => "ok"}
    # or an "unverified: reason" status and no stops.
    def probe(cdp, limit: LIMIT)
      dir = cdp.evaluate(RESET_JS)
      stops = walk(cdp, limit)
      cdp.evaluate(RESET_JS)
      return { "text_dir" => dir, "tab_order_status" => "unverified: Tab reached no focusable element" } if stops.empty?

      { "tab_order" => stops, "text_dir" => dir, "tab_order_status" => "ok" }
    rescue CdpSession::Error, KeyError => e
      { "tab_order_status" => "unverified: #{e.class.name.split("::").last} #{e.message[0, 80]}" }
    end

    # Stops until focus leaves the page, returns to the first stop, or stalls.
    def walk(cdp, limit)
      stops = []
      limit.times do
        cdp.press("Tab")
        stop = cdp.evaluate(ACTIVE_JS)
        break if stop.nil? || same?(stops.first, stop) && stops.size > 1 || same?(stops.last, stop)

        stops << stop
      end
      stops
    end

    def same?(a, b) = !a.nil? && a.values_at("sel", "x", "y") == b.values_at("sel", "x", "y")
  end
end
