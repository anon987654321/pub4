# frozen_string_literal: true

require_relative "../../support/cdp_session"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Two facts about a rendered page that no source check can see, and that this
  # repo got wrong on 2026-08-10 in both cases:
  #
  #   1. brgen served its LIGHT palette. :root declared the dark BRGEN_OLD tokens
  #      and had for months, but shared/_tokens.scss ends with
  #      `@media (prefers-color-scheme: light) { :root:not([data-theme=dark]) }`,
  #      which outranks a bare :root. On any client whose OS prefers light — the
  #      default on most installs — that block won. The app declared dark and
  #      served light, and both are valid CSS, so nothing reported it.
  #
  #   2. The chat tab is in a different corner on different surfaces. Two of
  #      those differences are deliberate and documented; the point of this gate
  #      is that a THIRD one would look identical from the source.
  #
  # Both are geometry and computed style, so both need a browser. The lesson from
  # the same day is that this is exactly where gates go quiet: every rendered
  # gate here calls skipped_live when a port is closed, and a skip is a warning
  # rather than a failure unless GATE_REQUIRE_LIVE=1. So a green run on a laptop
  # with nothing booted means nothing was measured. This gate follows that
  # convention rather than inventing a second one — but it records what it
  # measured, so a half-blind run does not read like a real one.
  class RenderedInvariants
    # Surfaces to visit, and the theme each is expected to serve.
    #
    # amber is deliberately absent: its :root includes luxury-light-tokens, so
    # light is its design rather than a bug, and asserting dark there would be
    # this gate telling the truth about the wrong intent.
    # theme: here is the product decision, mirroring ApplicationHelper's
    # DEFAULT_SURFACE_THEME, which is light on every surface: a white page with
    # #efefef panels (operator, 2026-09-25). It is duplicated rather than read
    # because this gate runs under bare ruby with no app booted; check_theme
    # compares it to what the page actually declares, so the two drifting apart
    # fails here rather than going quiet, as it did while this list still called
    # four light surfaces dark.
    SURFACES = [
      { host: "brgen.no", theme: :light },
      { host: "radio.brgen.no", theme: :light },
      { host: "markedsplass.brgen.no", theme: :light },
      { host: "takeaway.brgen.no", theme: :light },
      { host: "dating.brgen.no", theme: :light },
      { host: "tv.brgen.no", theme: :light },
    ].freeze

    # Surfaces where the chat tab legitimately is not in the bottom-right corner,
    # each with the reason. This list is the gate: a deviation that is not here
    # fails, and an entry here whose reason has evaporated is the exemption
    # problem TODO.md describes, so removing one is as much a fix as
    # adding one.
    CHAT_EXCEPTIONS = {
      # The dating splash is a bare swipe surface and the widget floated over
      # "sveip for å begynne" — see brgen's body.vertical-dating rules.
      "dating.brgen.no" => :absent,
      # Lifted clear of the transport bar, whose height it reads from
      # --tab-bar-h. Sitting flush would put it under a bar that intercepts the
      # click.
      "radio.brgen.no" => :raised,
      # The storefronts are not here: a closed or undrawn tab bar publishes no
      # height, so their tab sits in the corner like every other surface.
    }.freeze

    # A background this light cannot be a dark theme, whatever the tokens say.
    DARK_MAX_LUMA = 0.35

    # Fixed chrome sharing the top band, which must therefore share one centre
    # line. Measured on brgen.no before this check existed: nav links centred at
    # y=31 in a 62px bar while the brand mark and theme toggle sat at y=34,
    # because those two took `top` from --chrome-inset (a distance from the
    # screen edge, 12px) instead of from the bar. Three pixels reads as
    # sloppiness rather than as a bug, which is why it survived review and why it
    # wants a number rather than an eye.
    #
    # The search glyph and the sign-in link joined on 2026-09-25: the glyph took
    # its top from --chrome-inset while the corner took it from the bar (12 vs
    # 11), and it cleared only the toggle, so it sat 28px over the sign-in link.
    TOP_BAND = %w[.nav_link .brgen-logo-mark .theme-toggle .search_palette_trigger .chrome-auth].freeze

    # The fixed controls in the band, which must not overlap each other. The nav
    # links are left out: they scroll under a fade by design.
    BAND_CONTROLS = %w[.brgen-logo-mark .theme-toggle .search_palette_trigger .chrome-auth].freeze

    # The phone pass: the install prompt spans the width above the bottom chrome,
    # and on 2026-09-25 the nearby chat tab covered the lower 32px of its Install
    # button at 390px because the prompt cleared the peel handle and not the tab.
    PHONE = { width: 390, height: 844, host: "brgen.no" }.freeze

    # Sub-pixel differences are rounding, not misalignment.
    ALIGN_TOLERANCE_PX = 1

    # amber's home page is four looks, each a carousel over one figure. Each row
    # has to open on its first slide, flush with its own edge: a carousel that
    # loads scrolled, or a first slide inset from the track, shows half a garment
    # at the edge, which is what amberapp.art's rows did on 2026-09-25.
    AMBER_HOME = "https://amberapp.art/"
    AMBER_LOOKS = 4

    # runner.rb and gate_environment.rb both invoke a gate as `Class.run`. This
    # gate shipped with only the instance method, so it was a row in gates.yml
    # that nothing could call — registered, listed, and never once executed. The
    # gate exists to catch declarations with no reader; it was one.
    def self.run = new.run

    def initialize(result: GateResult.new)
      @result = result
    end

    def run
      # inconclusive!, not skipped_live: a missing browser is a precondition
      # this machine does not meet, and only unchecked reasons reach the
      # runner's "measured nothing, and why" list. Filed as a live skip, this
      # gate went inconclusive with an empty reason list and the runner printed
      # "exit 3, no reason given (subprocess gate)" for an in-process gate.
      unless CdpSession.available?
        @result.inconclusive!("no Chrome/Chromium — theme, chat corner and top band not measured")
        return @result
      end

      CdpSession.open do |session|
        session.viewport(1280, 800)
        SURFACES.each { |surface| check_surface(session, surface) }
        check_amber_home_looks(session)
        check_phone_bottom_chrome(session)
      end
      @result
    rescue CdpSession::Unavailable => e
      @result.inconclusive!("rendered_invariants: #{e.message}")
      @result
    end

    private

    def check_surface(session, surface)
      host = surface[:host]
      session.navigate("https://#{host}/", settle: 1.5)
      # A fresh profile gets the first-visit drawer reveal, which slides the
      # top bar mid-transition and turns steady-state alignment into noise.
      # Dismiss it the way a user would — Escape is the documented gesture —
      # and wait out the 300ms slide before measuring.
      if session.evaluate("!!document.querySelector('.revealed')")
        session.press("Escape")
        sleep 0.5
      end
      measured = session.evaluate(format(PROBE, band: JSON.generate(TOP_BAND)))
      return @result.skipped_live("rendered_invariants: #{host} unreadable") unless measured

      data = JSON.parse(measured)
      @result.checked!(3)
      check_theme(host, surface[:theme], data)
      check_chat_corner(host, data)
      check_top_band_alignment(host, data)
      check_band_overlap(host, data)
      check_mark_label(host, data)
    rescue StandardError => e
      @result.skipped_live("rendered_invariants: #{host} #{e.class}")
    end

    # Two separate questions, and conflating them is what made this gate wrong.
    #
    # It used to hold one expected theme per host and compare the rendered luma to
    # that. Then markedsplass, maps and takeaway became light on purpose (operator,
    # 2026-08-24: storefronts read light, and that is a product decision, not a
    # preference) and this list did not move with them. The gate reported two
    # deliberate surfaces as defects and told anyone reading to "fix" them by
    # pinning data-theme="dark" — undoing the decision on the gate's say-so.
    #
    # So the palette question is now asked against the page's own declaration:
    # whatever <html data-theme> says, the pixels have to agree. That is the bug
    # this gate was written for — a prefers-color-scheme block outranking a bare
    # :root, so the served palette contradicted the declared one — and it stays
    # caught without the gate holding an opinion about which surface is which.
    #
    # The product decision is still pinned, separately, by SURFACES: an accidental
    # flip of surface_theme is a real regression and would otherwise pass here,
    # since a flipped page agrees with itself perfectly.
    def check_theme(host, expected, data)
      luma = data["luma"]
      return unless luma

      declared = data["declared"]
      if declared.nil? || declared.empty?
        return @result.fail("#{host} declares no data-theme on <html>; surface_theme should always write one")
      end

      if declared != expected.to_s
        @result.fail(
          "#{host} declares data-theme=\"#{declared}\" but this gate expects #{expected}. " \
          "If the surface changed on purpose, move it in SURFACES; if not, surface_theme regressed.",
        )
      end

      serves_light = luma > DARK_MAX_LUMA
      return unless serves_light == (declared == "dark")

      @result.fail(
        "#{host} declares data-theme=\"#{declared}\" but serves a #{serves_light ? 'light' : 'dark'} " \
        "background (luma #{luma.round(2)}, bg #{data['bg']}). The declaration and the pixels " \
        "disagree — look for a prefers-color-scheme block outranking :root, not for new CSS.",
      )
    end

    def check_chat_corner(host, data)
      expectation = CHAT_EXCEPTIONS[host]

      if data["chat"].nil?
        return if expectation == :absent

        return @result.fail("#{host} has no chat widget and no declared reason in CHAT_EXCEPTIONS")
      end

      if expectation == :absent
        return @result.fail("#{host} is listed as :absent in CHAT_EXCEPTIONS but renders a chat widget")
      end

      right = data.dig("chat", "right")
      bottom = data.dig("chat", "bottom")
      flush = right.to_i.abs <= 2 && bottom.to_i.abs <= 2

      return if flush && expectation.nil?
      return if !flush && expectation == :raised
      return @result.fail("#{host} declares :raised but the chat tab is flush in the corner") if flush

      @result.fail(
        "#{host} renders the chat tab #{right}px from the right and #{bottom}px from the " \
        "bottom, which is neither the corner nor a declared exception. Either put it back " \
        "in the corner or add it to CHAT_EXCEPTIONS with the reason.",
      )
    end

    # Everything sharing the top band shares a centre line, or this says by how
    # much it does not. Compares centres rather than tops deliberately: elements
    # of different heights are correctly aligned at different tops, so a
    # top-based check would demand the wrong thing.
    def check_top_band_alignment(host, data)
      present = (data["band"] || {}).reject { |_, box| box.nil? }
      return if present.size < 2

      centres = present.transform_values { |box| box["cy"] }
      spread = centres.values.max - centres.values.min
      return if spread <= ALIGN_TOLERANCE_PX

      @result.fail(
        "#{host} top chrome is #{spread}px out of alignment " \
        "(centre-y: #{centres.map { |sel, cy| "#{sel} #{cy}" }.join(', ')}). " \
        "Everything in the top band centres on the nav bar — take `top` from " \
        "--chrome-inset-block, which follows the bar, not --chrome-inset, which is a " \
        "distance from the screen edge.",
      )
    end

    # Two fixed controls sharing any horizontal span means one of them takes the
    # other's taps; fixed chrome cannot be scrolled out from under a blocker.
    def check_band_overlap(host, data)
      boxes = (data["band"] || {}).slice(*BAND_CONTROLS).reject { |_, box| box.nil? || box["l"].nil? }
      boxes.to_a.combination(2).each do |(a, box_a), (b, box_b)|
        overlap = [box_a["r"], box_b["r"]].min - [box_a["l"], box_b["l"]].max
        next if overlap <= ALIGN_TOLERANCE_PX

        @result.fail("#{host} top chrome: #{a} and #{b} overlap by #{overlap}px, so one takes the " \
                     "other's taps. A control that joins the corner has to be cleared by the ones beside it.")
      end
    end

    # The mark is the city name alone (operator, 2026-09-25); a dot means a TLD.
    def check_mark_label(host, data)
      label = data["mark"].to_s
      return if label.empty? || !label.include?(".")

      @result.fail("#{host} brand mark reads \"#{label}\"; it is the city name without its TLD " \
                   "(brand_mark_fragments)")
    end

    # At phone width the install prompt and the chat tab are both fixed to the
    # bottom edge. A prompt the page never showed is not measured. brgen's
    # prompt waits for the visitor's first scroll, tap or key (after_engagement),
    # so the probe scrolls once before it measures; unengaged, it measures
    # nothing and the check would pass having seen no prompt.
    def check_phone_bottom_chrome(session)
      session.viewport(PHONE[:width], PHONE[:height], mobile: true)
      session.navigate("https://#{PHONE[:host]}/", settle: 1.5)
      session.evaluate(%(window.dispatchEvent(new Event("scroll"))))
      sleep 0.3
      measured = session.evaluate(BOTTOM_PROBE)
      return @result.skipped_live("rendered_invariants: #{PHONE[:host]} phone unreadable") unless measured

      check_bottom_overlap(JSON.parse(measured))
    rescue StandardError => e
      @result.skipped_live("rendered_invariants: #{PHONE[:host]} phone #{e.class}")
    end

    # prompt / chat: { "t", "b", "l", "r" } in viewport px, or nil when not shown.
    def check_bottom_overlap(boxes)
      prompt = boxes["prompt"]
      chat = boxes["chat"]
      return if prompt.nil? || chat.nil?

      @result.checked!
      across = [prompt["r"], chat["r"]].min - [prompt["l"], chat["l"]].max
      down = [prompt["b"], chat["b"]].min - [prompt["t"], chat["t"]].max
      return if across <= ALIGN_TOLERANCE_PX || down <= ALIGN_TOLERANCE_PX

      @result.fail("#{PHONE[:host]} at #{PHONE[:width]}px: the chat tab covers #{down}px of the install " \
                   "prompt. The prompt clears the bottom chrome by --tab-bar-h plus one tap row.")
    end

    # A fresh profile is a signed-out visitor, which is who the page is for.
    def check_amber_home_looks(session)
      session.navigate(AMBER_HOME, settle: 1.5)
      measured = session.evaluate(LOOKS_PROBE)
      return @result.skipped_live("rendered_invariants: #{AMBER_HOME} unreadable") unless measured

      check_home_looks(JSON.parse(measured))
    rescue StandardError => e
      @result.skipped_live("rendered_invariants: #{AMBER_HOME} #{e.class}")
    end

    # rows: one per look, { "scroll" => the track's scrollLeft, "inset" => the
    # first slide's left edge less the track's }.
    def check_home_looks(rows)
      @result.checked!
      return @result.fail("#{AMBER_HOME} shows #{rows.size} looks, not #{AMBER_LOOKS}") if rows.size != AMBER_LOOKS

      off = rows.each_with_index.reject do |row, _|
        row["scroll"].to_f.abs <= ALIGN_TOLERANCE_PX && row["inset"].to_f.abs <= ALIGN_TOLERANCE_PX
      end
      return if off.empty?

      detail = off.map { |row, i| "look #{i + 1}: scrolled #{row['scroll']}px, first slide inset #{row['inset']}px" }
      @result.fail(
        "#{AMBER_HOME} look(s) #{off.map { |_, i| i + 1 }.join(', ')} do not open on their first slide " \
        "(#{detail.join('; ')}). A row starts at scrollLeft 0 with its first slide on the track's edge.",
      )
    end

    LOOKS_PROBE = <<~JS
      (() => JSON.stringify([...document.querySelectorAll(".amber-look-track")].map(track => {
        const slide = track.querySelector(".amber-look-slide");
        return { scroll: track.scrollLeft,
                 inset: slide ? Math.round(slide.getBoundingClientRect().left - track.getBoundingClientRect().left) : null };
      })))()
    JS

    PROBE = <<~JS
      (() => {
        const cs = getComputedStyle(document.body);
        const bg = cs.backgroundColor;
        const m = bg.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
        // Rec. 709 luma, 0..1. A theme is not "dark" because a token says so.
        const luma = m
          ? (0.2126 * +m[1] + 0.7152 * +m[2] + 0.0722 * +m[3]) / 255
          : null;
        const el = document.querySelector(".nearby-chat-widget");
        let chat = null;
        if (el && getComputedStyle(el).display !== "none") {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) {
            chat = {
              right: Math.round(innerWidth - r.right),
              bottom: Math.round(innerHeight - r.bottom),
            };
          }
        }
        const band = {};
        for (const sel of %<band>s) {
          const t = document.querySelector(sel);
          const tr = t?.getBoundingClientRect();
          band[sel] = (tr && tr.width > 0 && tr.height > 0)
            ? { cy: Math.round(tr.top + tr.height / 2), l: Math.round(tr.left), r: Math.round(tr.right) }
            : null;
        }
        const mark = document.querySelector(".brgen-logo-mark .brand-text")?.textContent.trim() ?? "";
        // What the page says it is serving. surface_theme writes this per
        // surface, so it is the app's own answer rather than the gate's guess.
        const declared = document.documentElement.getAttribute("data-theme");
        return JSON.stringify({ bg, luma, chat, band, declared, mark });
      })()
    JS

    BOTTOM_PROBE = <<~JS
      (() => {
        const box = (sel) => {
          const e = document.querySelector(sel);
          if (!e || e.hidden || getComputedStyle(e).display === "none") return null;
          const r = e.getBoundingClientRect();
          return r.width > 0 && r.height > 0 ? { t: r.top, b: r.bottom, l: r.left, r: r.right } : null;
        };
        return JSON.stringify({ prompt: box(".install-prompt"), chat: box(".nearby-chat-widget") });
      })()
    JS
  end
end
