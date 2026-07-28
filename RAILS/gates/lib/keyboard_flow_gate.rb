# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "geometry_probe"

module Deploy
  # Keyboard reachability, measured by pressing Tab.
  #
  # Nothing in the existing suite touches the keyboard. That matters here more
  # than usual because of a live tension in the design system: design_tokens.yml
  # defines focus_ring as "2px solid var(--accent)", while the flat_ui contract
  # forbids box-shadow — so the ring has to come from `outline`, and an
  # `outline: none` anywhere silently removes the only focus affordance the
  # system has. This gate walks the real tab order and checks that each stop
  # renders a visible ring.
  class KeyboardFlowGate
    ROOT = File.expand_path("../../..", __dir__)
    MAX_TABS = 25

    ACTIVE = <<~JS
      (() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        const cs = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        const cls = String(el.className || '').split(' ').filter(Boolean).slice(0, 2).join('.');
        const outlineWidth = parseFloat(cs.outlineWidth) || 0;
        const hasOutline = cs.outlineStyle !== 'none' && outlineWidth > 0;
        const hasShadow = cs.boxShadow && cs.boxShadow !== 'none';
        const hasBorderChange = cs.borderStyle !== 'none' && (parseFloat(cs.borderWidth) || 0) > 0;
        return {
          sel: el.tagName.toLowerCase() + (el.id ? '#' + el.id : (cls ? '.' + cls : '')),
          tag: el.tagName.toLowerCase(),
          href: el.getAttribute('href') || null,
          text: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().slice(0, 40),
          tabindex: el.getAttribute('tabindex'),
          rect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
          doc_order: Array.prototype.indexOf.call(document.querySelectorAll('*'), el),
          ring: hasOutline || hasShadow,
          ring_kind: hasOutline ? 'outline' : (hasShadow ? 'box-shadow' : (hasBorderChange ? 'border-only' : 'none')),
          onscreen: r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight
        };
      })()
    JS

    def self.run = new.run

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.warn("keyboard_flow: no Chrome/Chromium — tab order not walked")
        return @result
      end

      surfaces = pick_surfaces
      GeometryProbe.unreachable_apps(surfaces).each { |app| @result.warn("keyboard_flow: #{app} port closed — skipped") }
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.warn("keyboard_flow: no app reachable")
        return @result
      end

      GeometryProbe.with_browser do |cdp|
        live.each { |surface| walk_tab_order(cdp, surface) }
      end
      @result.warn("keyboard_flow: walked tab order on #{live.size} surface(s)")
      @result
    end

    private

    def pick_surfaces
      GeometryProbe.surfaces
                   .select { |s| s.viewport == "desktop" }
                   .uniq { |s| "#{s.app}/#{s.label}" }
                   .group_by(&:app)
                   .flat_map { |_app, rows| rows.first(2) }
    end

    def walk_tab_order(cdp, surface)
      label = "#{surface.app}/#{surface.label}"
      payload = GeometryProbe.walk(cdp, surface)
      unless GeometryProbe.ok?(payload)
        @result.fail("keyboard_flow: #{label} unreachable (#{payload["error"] || "HTTP #{payload["status"]}"})")
        return
      end

      begin
        cdp.evaluate("document.body.focus(); if (document.activeElement) document.activeElement.blur();")
      rescue CdpSession::Error
        nil
      end

      stops = []
      MAX_TABS.times do
        cdp.press("Tab")
        stop = begin
          cdp.evaluate(ACTIVE)
        rescue CdpSession::Error
          nil
        end
        break if stop.nil?

        stops << stop
        break if stops.size >= 2 && stop["sel"] == stops[-2]["sel"] && stop["doc_order"] == stops[-2]["doc_order"]
      end

      if stops.empty?
        @result.fail("keyboard_flow: #{label} has no keyboard-reachable element in #{MAX_TABS} tabs — " \
                     "the page cannot be operated without a mouse")
        return
      end

      check_skip_link_first(label, stops)
      check_document_order(label, stops)
      check_focus_ring(label, stops)
      check_offscreen_focus(label, stops)
    end

    # The skip link exists so a keyboard user does not tab through the whole
    # nav. It only works if it is the first stop.
    def check_skip_link_first(label, stops)
      index = stops.index { |s| s["href"] == "#main-content" || s["sel"].to_s.include?("skip") }
      if index.nil?
        @result.fail("keyboard_flow: #{label} skip link is not reachable by keyboard in #{stops.size} tabs " \
                     "(it is in the HTML but never receives focus)", severity: :soft)
      elsif index.positive?
        before = stops.first(index).map { |s| s["sel"] }.join(", ")
        @result.fail("keyboard_flow: #{label} skip link is tab stop ##{index + 1}, not first — " \
                     "reached only after #{before} (principle=accessibility)")
      end
    end

    # A tab order that jumps backwards through the document is almost always a
    # positive tabindex or a mis-ordered DOM, and it disorients screen readers.
    def check_document_order(label, stops)
      positive = stops.select { |s| s["tabindex"].to_i.positive? }
      unless positive.empty?
        @result.fail("keyboard_flow: #{label} uses positive tabindex on #{positive.map { |s| s["sel"] }.uniq.join(', ')} — " \
                     "this overrides document order for the whole page", severity: :soft)
      end

      inversions = stops.each_cons(2).count { |a, b| b["doc_order"].to_i < a["doc_order"].to_i }
      return if inversions.zero?

      @result.fail("keyboard_flow: #{label} tab order jumps backwards #{inversions}× through the document " \
                   "(focus order does not follow reading order)", severity: :soft)
    end

    def check_focus_ring(label, stops)
      ringless = stops.select { |s| s["onscreen"] && !s["ring"] }
      return if ringless.empty?

      sample = ringless.first(3).map { |s| "#{s["sel"]} (#{s["ring_kind"]})" }.join(", ")
      @result.fail(
        "keyboard_flow: #{label} #{ringless.size}/#{stops.size} focus stops render no visible ring — #{sample}. " \
        "design_tokens focus_ring is '2px solid', and flat_ui forbids box-shadow, so this must come from outline " \
        "(principle=accessibility)"
      )
    end

    # Focus that lands on something off-screen means the user is typing into a
    # control they cannot see — a closed drawer or an unclosed modal.
    def check_offscreen_focus(label, stops)
      hidden = stops.select { |s| !s["onscreen"] }
      return if hidden.size < 3

      @result.fail(
        "keyboard_flow: #{label} #{hidden.size}/#{stops.size} tab stops are off-screen " \
        "(e.g. #{hidden.first(2).map { |s| s["sel"] }.join(', ')}) — keyboard focus enters a hidden region",
        severity: :soft
      )
    end
  end
end
