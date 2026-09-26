# frozen_string_literal: true

require "json"
require "uri"

module Deploy
  module CompositionProbe
    DANGEROUS_TEXT = /\b(?:delete|remove|destroy|send|submit|post|publish|save|buy|purchase|checkout|pay|sign\s*out|log\s*out|logout|follow|unfollow|like|unlike|favorite|unfavorite|confirm|register|sign\s*in|log\s*in|accept|decline|block|unblock|mute|unmute|archive|restore|join|leave)\b/i
    MAX_PAIRS = Integer(ENV.fetch("MASTER_VISUAL_COMPOSITION_PAIRS", "4"))

    # The page-side scripts, kept as data so each Ruby method stays about one
    # step. They are single-quoted heredocs: in a double-quoted one Ruby reads
    # the regex escape \s as a space, and the label and aria-controls splits
    # then broke on spaces only, never on the newlines textContent carries.
    DISCOVER_JS = <<~'JS'.sub("__DANGEROUS__") { DANGEROUS_TEXT.inspect }
      (() => {
        const visible = (el) => {
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 1 && r.height > 1 &&
            s.display !== "none" && s.visibility !== "hidden" && s.pointerEvents !== "none";
        };
        const disabled = (el) => el.disabled || el.getAttribute("aria-disabled") === "true";
        const ignored = (el) => el.closest("[data-master-composition-ignore='true']");
        const label = (el) => (
          el.getAttribute("aria-label") ||
          el.getAttribute("title") ||
          el.textContent ||
          el.getAttribute("name") ||
          ""
        ).replace(/\s+/g, " ").trim().slice(0, 100);
        const dangerous = (el) => __DANGEROUS__.test([
          label(el),
          el.getAttribute("data-action"),
          el.getAttribute("formaction")
        ].filter(Boolean).join(" "));
        const path = (el) => {
          const parts = [];
          while (el && el.nodeType === 1 && el !== document.body) {
            let n = 1;
            for (let sib = el.previousElementSibling; sib; sib = sib.previousElementSibling) {
              if (sib.tagName === el.tagName) n++;
            }
            parts.unshift(el.tagName.toLowerCase() + ":nth-of-type(" + n + ")");
            el = el.parentElement;
          }
          return "body > " + parts.join(" > ");
        };

        return JSON.stringify([...document.querySelectorAll("button, summary, [role='button']")]
          .filter((el) => {
            if (!visible(el) || disabled(el) || ignored(el) || dangerous(el)) return false;
            if (el.matches("button")) {
              const type = (el.getAttribute("type") || "submit").toLowerCase();
              if (!["button", "menu"].includes(type)) return false;
            }
            if (el.matches("summary") && el.closest("details[open]")) return false;
            const text = label(el);
            return text.length > 0;
          })
          .map((el) => ({
            selector: path(el),
            label: label(el),
            tag: el.tagName.toLowerCase(),
            stateful: Boolean(
              el.hasAttribute("aria-expanded") ||
              el.hasAttribute("aria-pressed") ||
              el.hasAttribute("aria-selected") ||
              el.hasAttribute("aria-controls") ||
              el.matches("summary, [popovertarget]")
            )
          })));
      })()
    JS

    # __SELECTOR__ is replaced with the candidate's selector as a JSON string.
    STATE_JS = <<~'JS'
      (() => {
        const visible = (el) => {
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 1 && r.height > 1 && s.display !== "none" && s.visibility !== "hidden";
        };
        const candidate = document.querySelector(__SELECTOR__);
        const controlled = candidate?.getAttribute("aria-controls")?.split(/\s+/).filter(Boolean).map((id) => {
          const el = document.getElementById(id);
          return el ? {
            id,
            hidden: el.hidden,
            visible: visible(el),
            open: el.matches("dialog[open], details[open], [popover]:popover-open"),
            className: el.className?.toString().slice(0, 160)
          } : null;
        }).filter(Boolean);
        return JSON.stringify({
          url: location.pathname + location.search,
          theme: document.documentElement.dataset.theme || "",
          html_class: document.documentElement.className.toString().slice(0, 160),
          body_class: document.body.className.toString().slice(0, 160),
          candidate: candidate ? {
            expanded: candidate.getAttribute("aria-expanded"),
            pressed: candidate.getAttribute("aria-pressed"),
            selected: candidate.getAttribute("aria-selected"),
            current: candidate.getAttribute("aria-current"),
            hidden: candidate.hidden,
            open: candidate.matches("dialog[open], details[open], [popover]:popover-open"),
            className: candidate.className?.toString().slice(0, 160),
            active: document.activeElement === candidate
          } : null,
          controlled,
          dialogs: document.querySelectorAll("dialog[open]").length,
          details: document.querySelectorAll("details[open]").length,
          popovers: document.querySelectorAll("[popover]:popover-open").length,
          visible_menus: [...document.querySelectorAll("[role='menu'], [role='listbox'], [role='dialog'], [role='tabpanel']")].filter(visible).length
        });
      })()
    JS

    CLICK_JS = <<~'JS'
      (() => {
        const el = document.querySelector(__SELECTOR__);
        if (!el) return false;
        el.click();
        return true;
      })()
    JS

    EDITABLE_JS = <<~'JS'
      (() => {
        const visible = (el) => {
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 1 && r.height > 1 && s.display !== "none" && s.visibility !== "hidden";
        };
        const field = [...document.querySelectorAll("dialog[open] textarea, dialog[open] input[type='text'], dialog[open] input[type='search'], [role='dialog'] textarea, [role='dialog'] input[type='text'], [role='dialog'] input[type='search'], [contenteditable='true']")]
          .find((el) => visible(el) && !el.disabled && !el.readOnly);
        if (!field) return false;
        field.focus();
        if ("value" in field) {
          field.value = "MASTER visual probe";
          field.dispatchEvent(new Event("input", { bubbles: true }));
          field.dispatchEvent(new Event("change", { bubbles: true }));
        } else {
          field.textContent = "MASTER visual probe";
          field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: "MASTER visual probe" }));
        }
        return field.getAttribute("aria-label") || field.getAttribute("placeholder") || field.getAttribute("name") || field.tagName.toLowerCase();
      })()
    JS

    class << self
      def capture(cdp, surface, dir:, pass:, limit: 12)
        candidates = discover(cdp)
        return [] if candidates.empty?

        offset = ((pass.to_i - 1) * limit) % candidates.length
        singles = candidates.rotate(offset).first(limit)
        captures = singles.filter_map.with_index do |candidate, index|
          capture_candidate(cdp, surface, candidate, dir:, index:)
        end.flatten

        stateful = singles.select { |candidate| candidate["stateful"] }
        pair_offset = ((pass.to_i - 1) * [MAX_PAIRS, 1].max) % [stateful.length, 1].max
        stateful.rotate(pair_offset).each_slice(2).first(MAX_PAIRS).each_with_index do |pair, index|
          next unless pair.length == 2

          captures.concat(capture_pair(cdp, surface, pair, dir:, index:))
        end
        captures
      end

      private

      def discover(cdp)
        JSON.parse(cdp.evaluate(DISCOVER_JS).to_s)
      rescue JSON::ParserError => e
        raise "composition discovery returned invalid JSON: #{e.message}"
      end

      # One control clicked on a fresh load, then, when the state it opened holds
      # a text field, a second capture with that field typed into.
      def capture_candidate(cdp, surface, candidate, dir:, index:)
        selector = candidate.fetch("selector")
        cdp.navigate(surface.url)
        return unless wait_until(cdp, "document.readyState === 'complete'")
        return unless cdp.evaluate("!!document.querySelector(#{selector.to_json})")

        before = state_signature(cdp, selector)
        return unless click_and_wait(cdp, candidate) && same_surface?(cdp, surface)

        after = wait_for_state_change(cdp, before, selector)
        return unless after

        state_surface = derived_surface(surface, "#{surface.label}__interaction_#{index + 1}")
        opened = record(cdp, surface, state_surface, dir:) do
          { "state" => "interaction", "base_surface" => surface.id, "trigger" => candidate.fetch("label"),
            "trigger_selector" => selector, "state_signature" => after }
        end
        return unless opened

        [opened, draft_capture(cdp, surface, state_surface, candidate, dir:)].compact
      end

      def draft_capture(cdp, surface, state_surface, candidate, dir:)
        field = editable_probe(cdp)
        return unless field

        draft_surface = derived_surface(surface, "#{state_surface.label}__input")
        record(cdp, surface, draft_surface, dir:) do
          { "state" => "interaction_input", "base_surface" => surface.id, "trigger" => candidate.fetch("label"),
            "trigger_selector" => candidate.fetch("selector"), "field" => field,
            "state_signature" => state_signature(cdp, candidate.fetch("selector")) }
        end
      end

      def capture_pair(cdp, surface, pair, dir:, index:)
        first, second = pair
        cdp.navigate(surface.url)
        return [] unless wait_until(cdp, "document.readyState === 'complete'")
        return [] unless click_and_wait(cdp, first)

        before = state_signature(cdp, second.fetch("selector"))
        return [] unless cdp.evaluate("!!document.querySelector(#{second.fetch("selector").to_json})")
        return [] unless click_and_wait(cdp, second)

        after = wait_for_state_change(cdp, before, second.fetch("selector"))
        return [] unless after && same_surface?(cdp, surface)

        state_surface = derived_surface(surface, "#{surface.label}__pair_#{index + 1}")
        Array(record(cdp, surface, state_surface, dir:) do
          { "state" => "interaction_pair", "base_surface" => surface.id,
            "triggers" => [first.fetch("label"), second.fetch("label")],
            "trigger_selectors" => [first.fetch("selector"), second.fetch("selector")], "state_signature" => after }
        end)
      end

      # A copy of the base surface under a new label, never snapshotted: these
      # states are judged, not committed as baselines.
      def derived_surface(surface, label)
        GeometryProbe::Surface.new(
          app: surface.app, label:, host: surface.host, path: surface.path, viewport: surface.viewport,
          width: surface.width, height: surface.height, snapshot: false, port: surface.port, profile: surface.profile
        )
      end

      # Measures the page as it stands, tags it with the composition the block
      # describes, and screenshots it. nil when the measurement did not come back.
      def record(cdp, surface, state_surface, dir:)
        payload = GeometryProbe.measure_current(cdp, state_surface)
        return unless GeometryProbe.ok?(payload)

        payload["composition"] = yield
        shot = File.join(dir, "#{safe_slug(state_surface.id)}.png")
        cdp.screenshot(shot, capture_beyond_viewport: true)
        { surface: state_surface, payload:, screenshot: shot, journeys: [],
          platform: surface.viewport == "mobile" ? WebPlatformProbe.run(cdp, state_surface) : {} }
      end

      def state_signature(cdp, selector)
        JSON.parse(cdp.evaluate(STATE_JS.sub("__SELECTOR__") { selector.to_json }).to_s)
      rescue JSON::ParserError => e
        raise "composition state signature invalid JSON: #{e.message}"
      end

      def wait_for_state_change(cdp, before, selector, timeout: 2.0)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          after = state_signature(cdp, selector)
          return after if after != before
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.05
        end
      end

      def click_and_wait(cdp, candidate)
        clicked = cdp.evaluate(CLICK_JS.sub("__SELECTOR__") { candidate.fetch("selector").to_json })
        clicked && wait_until(cdp, "document.readyState === 'complete'", timeout: 1.5)
      end

      def same_surface?(cdp, surface)
        location = URI.parse(cdp.evaluate("location.href").to_s)
        expected = URI.parse(surface.url)
        "#{location.path}#{location.query ? "?#{location.query}" : ""}" == "#{expected.path}#{expected.query ? "?#{expected.query}" : ""}"
      end

      def editable_probe(cdp) = cdp.evaluate(EDITABLE_JS)

      def wait_until(cdp, expression, timeout: 3.0)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return true if cdp.evaluate(expression)
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.05
        end
      end

      def safe_slug(value) = value.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")
    end
  end
end
