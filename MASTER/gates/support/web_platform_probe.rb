# frozen_string_literal: true

require "json"

module Deploy
  class WebPlatformProbe
    # Runtime evidence for modern platform opportunities and brittle legacy
    # workarounds. This never mutates the page.
    SCRIPT = <<~JS
      (() => {
        const visible = el => {
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 0 && r.height > 0 &&
            s.display !== "none" && s.visibility !== "hidden";
        };
        const all = [...document.querySelectorAll("*")];
        const controls = all.filter(el => visible(el) &&
          /^(INPUT|SELECT|TEXTAREA|BUTTON)$/.test(el.tagName));
        const data = {
          viewport: { width: innerWidth, height: innerHeight },
          overflow: {
            document: document.documentElement.scrollWidth > document.documentElement.clientWidth,
            body: document.body ? document.body.scrollWidth > document.body.clientWidth : false
          },
          fixed_height_containers: all.filter(el => {
            const s = getComputedStyle(el);
            return visible(el) && s.height.endsWith("px") &&
              parseFloat(s.height) >= 200 && (el.scrollHeight > el.clientHeight || el.innerText.length > 160);
          }).length,
          fixed_width_containers: all.filter(el => {
            const s = getComputedStyle(el);
            return visible(el) && s.width.endsWith("px") &&
              parseFloat(s.width) >= 320 && parseFloat(s.width) > innerWidth * 0.9;
          }).length,
          modern_viewport_units: all.some(el => {
            const s = getComputedStyle(el);
            return /dvh|svh|lvh/.test(s.height + s.minHeight + s.maxHeight);
          }),
          small_form_text: controls.filter(el => {
            const s = getComputedStyle(el);
            return /^(INPUT|SELECT|TEXTAREA)$/.test(el.tagName) && parseFloat(s.fontSize) < 16;
          }).length,
          disclosure: all.some(el => el.matches("dialog, [popover], details")),
          anchor_positioning: all.some(el => {
            const s = getComputedStyle(el);
            return s.positionAnchor || s.anchorName || s.positionArea;
          }),
          view_transition: typeof document.startViewTransition === "function",
          reduced_motion: matchMedia("(prefers-reduced-motion: reduce)").matches,
          interactive_small_targets: controls.filter(el => {
            const r = el.getBoundingClientRect();
            return r.width < 44 || r.height < 44;
          }).length
        };
        return JSON.stringify(data);
      })()
    JS

    def self.run(cdp, surface)
      return {} unless surface.viewport == "mobile"

      payload = JSON.parse(cdp.evaluate(SCRIPT).to_s)
      raise "web_platform: browser returned a non-object payload" unless payload.is_a?(Hash)

      payload
    rescue JSON::ParserError => e
      raise "web_platform: browser returned invalid JSON (#{e.message})"
    rescue StandardError => e
      raise "web_platform: runtime probe failed (#{e.class}: #{e.message})"
    end
  end
end
