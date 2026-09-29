# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"

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
    ROOT = File.expand_path("../../../..", __dir__)
    MAX_TABS = 25

    FOCUS_RESET = <<~JS
      (() => {
        if (document.activeElement && document.activeElement !== document.body) {
          document.activeElement.blur();
        }
        document.body.setAttribute("tabindex", "-1");
        document.body.focus();
        const a = document.activeElement;
        return !a || a === document.body || a === document.documentElement;
      })()
    JS

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

    # Interaction states beyond focus. A control has to look different when it
    # is pressed, when it cannot be pressed and when it is working, or a reader
    # presses twice, presses a dead button, or leaves a form mid-submit.
    # :active cannot be reached from script, so it is forced over CDP; disabled
    # and aria-busy are set from script, read and taken off again.
    STATE_MARK = File.read(File.join(__dir__, "../../support/journey_probe/state_mark.js")).freeze
    STATE_READ = File.read(File.join(__dir__, "../../support/journey_probe/state_read.js")).freeze
    STATES = %w[active disabled busy].freeze
    STATE_WHY = {
      "active" => "a press gives no feedback, so it is pressed again",
      "disabled" => "a control that cannot be pressed looks like one that can",
      "busy" => "a form mid-submit looks idle and is submitted twice",
    }.freeze

    def self.run = new.run

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("keyboard_flow: no Chrome/Chromium — tab order not walked")
        return @result
      end

      surfaces = pick_surfaces
      GeometryProbe.unreachable_apps(surfaces).each { |app| @result.skipped_live("keyboard_flow: #{app} port closed — skipped") }
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("keyboard_flow: no app reachable")
        return @result
      end

      measured = 0
      GeometryProbe.with_browser do |cdp|
        live.each { |surface| measured += 1 if walk_tab_order(cdp, surface) }
      end
      # Counted per surface walked, so one surface that could not be measured
      # does not make the ones that were count for nothing — and a run where
      # every surface refused to release focus, or timed out, walked no tab order
      # at all. Both of those are warnings or unchecked preconditions rather than
      # failures, so counting attempts reported them as a pass.
      if measured.zero?
        @result.inconclusive!("keyboard_flow: 0/#{live.size} surface(s) yielded a tab order — nothing was walked")
        return @result
      end
      # Findings from the surfaces that were walked still block; only the pass is
      # withheld, because two walked pages do not make a tab order sound.
      if GeometryProbe.too_few_measured?(measured, live.size)
        @result.inconclusive!("keyboard_flow: walked #{measured}/#{live.size} surface(s) — too few to call " \
                              "the tab order sound; warm the apps and re-run")
        return @result
      end

      @result.checked!(measured)
      @result.warn("keyboard_flow: walked tab order on #{measured} surface(s)")
      @result
    end

    private

    def pick_surfaces
      # Prefer high-traffic triangle surfaces first (home/nearby/wardrobe/feed),
      # then fill remaining slots so keyboard order is not only auth forms.
      preferred = %w[
        brgen/core brgen/nearby brgen/marketplace brgen/session_new
        amber/home amber/wardrobe amber/feed amber/sign_in
      ]
      desktop = GeometryProbe.surfaces
                             .select { |s| s.viewport == "desktop" }
                             .uniq { |s| "#{s.app}/#{s.label}" }
      by_key = {}
      desktop.each { |s| by_key["#{s.app}/#{s.label}"] = s }
      picked = preferred.filter_map { |k| by_key[k] }
      # Up to 3 additional per app for breadth
      desktop.group_by(&:app).each_value do |rows|
        rows.each do |s|
          break if picked.count { |p| p.app == s.app } >= 4
          picked << s unless picked.include?(s)
        end
      end
      picked
    end

    def walk_tab_order(cdp, surface)
      label = "#{surface.app}/#{surface.label}"
      payload = GeometryProbe.walk(cdp, surface)
      unless GeometryProbe.ok?(payload)
        err = payload["error"] || "HTTP #{payload["status"]}"
        if err.to_s.match?(/timeout|Timeout/i)
          @result.warn("keyboard_flow: #{label} skipped (#{err})")
        else
          @result.fail("keyboard_flow: #{label} unreachable (#{err})")
        end
        return false
      end

      # Start the walk from the top of the document, provably.
      #
      # `document.body.focus()` is a no-op on a body with no tabindex, so on any
      # page with an autofocus field the blur that follows ran against the
      # autofocused element and Chrome kept focus inside the form. The walk then
      # began mid-document and wrapped, so a skip link that is genuinely tab stop
      # #1 was reported as #16 — measured on amber /session/new, whose
      # `<input autofocus id="email_address">` put `input#password` first and the
      # skip link only after the wrap. That is an artifact of where the walk
      # started, not a defect in the page, and it is exactly the assertion this
      # gate uses to claim a skip link is misplaced.
      #
      # Giving body tabindex=-1 makes focus() actually land, and asserting
      # activeElement is body (or nothing) before tabbing means a page that fights
      # the reset is reported as unmeasurable rather than silently mismeasured.
      focus_reset = begin
        cdp.evaluate(FOCUS_RESET)
      rescue CdpSession::Error
        nil
      end

      unless focus_reset
        @result.inconclusive!(
          "keyboard_flow: #{label} would not release focus to the document, so tab order " \
          "could not be measured from the start (an autofocus field holding focus reads as a " \
          "misplaced skip link)"
        )
        return false
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
        return true
      end

      check_skip_link_first(label, stops)
      check_document_order(label, stops)
      check_focus_ring(label, stops)
      check_offscreen_focus(label, stops)
      judge_states(label, read_states(cdp))
      true
    end

# One row per marked control: its painted state at rest and under each of
# STATES. A read that fails costs that control, not the walk.
    def read_states(cdp)
      selectors = cdp.evaluate(STATE_MARK)
      return [] unless selectors.is_a?(Array)

      selectors.each_with_index.filter_map do |sel, index|
        rest = paint(cdp, index, "none")
        next unless rest

        { "sel" => sel, "rest" => rest, "active" => forced_active(cdp, index),
          "disabled" => paint(cdp, index, "disabled"), "busy" => paint(cdp, index, "busy") }
      end
    rescue CdpSession::Error
      []
    end

    def paint(cdp, index, mutation)
      cdp.evaluate(STATE_READ.sub("__INDEX__", index.to_s).sub("__MUTATION__", mutation))
    end

    def forced_active(cdp, index)
      selector = %([data-gate-state="#{index}"])
      return nil unless cdp.force_pseudo_state(selector, ["active"])

      paint(cdp, index, "none")
    ensure
      cdp.force_pseudo_state(selector, []) if selector
    end

    public

    # The verdict on the state rows of one surface. A state reads as missing when
    # its paint equals the paint at rest; a state that could not be read (nil) is
    # left out of both counts rather than scored as present or absent.
    def judge_states(label, rows, result: @result)
      @result = result
      counts = STATES.map do |state|
        read = rows.reject { |row| row[state].nil? }
        flat = read.select { |row| row[state] == row["rest"] }
        report_flat_state(label, state, flat, read.size) unless flat.empty?
        "#{state} #{flat.size}/#{read.size}"
      end
      @result.warn("keyboard_flow states: #{label} unpainted #{counts.join(", ")}") unless rows.empty?
      @result
    end

    private

    def report_flat_state(label, state, flat, total)
      @result.fail("keyboard_flow states: #{label} #{flat.size}/#{total} controls paint no #{state} state " \
                   "(e.g. #{flat.first(2).map { |row| row["sel"] }.join(", ")}) — #{STATE_WHY.fetch(state)}",
                   severity: :soft)
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
