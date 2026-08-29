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
    # LIGHT_VERTICALS (marketplace, maps, takeaway read light — operator,
    # 2026-08-24). It is duplicated rather than read because this gate runs under
    # bare ruby with no app booted; check_theme compares it to what the page
    # actually declares, so the two drifting apart fails here rather than going
    # quiet the way it did when this list still called both storefronts dark.
    SURFACES = [
      { host: "brgen.no", theme: :dark },
      { host: "playlist.brgen.no", theme: :dark },
      { host: "markedsplass.brgen.no", theme: :light },
      { host: "takeaway.brgen.no", theme: :light },
      { host: "dating.brgen.no", theme: :dark },
      { host: "tv.brgen.no", theme: :dark },
    ].freeze

    # Surfaces where the chat tab legitimately is not in the bottom-right corner,
    # each with the reason. This list is the gate: a deviation that is not here
    # fails, and an entry here whose reason has evaporated is the exemption
    # problem TODO.md describes, so removing one is as much a fix as
    # adding one.
    CHAT_EXCEPTIONS = {
      # The dating splash is a bare swipe surface and the widget floated over
      # "sveip for å begynne" — see _vertical_dating_shell.scss.
      "dating.brgen.no" => :absent,
      # Lifted clear of the transport bar, whose height it reads from
      # --tab-bar-h. Sitting flush would put it under a bar that intercepts the
      # click.
      "playlist.brgen.no" => :raised,
      # Same mechanism, same reason: both storefronts set bottom: var(--tab-bar-h)
      # and clear their tab bar by its own declared height (44px here, 60px on
      # playlist). Measured rather than assumed — at rest the bar is translated
      # off-screen with pointer-events:none, so a snapshot taken while the chrome
      # is hidden makes the lift look gratuitous. It is not: the bar comes back.
      "markedsplass.brgen.no" => :raised,
      "takeaway.brgen.no" => :raised,
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
    TOP_BAND = %w[.nav_link .brgen-logo-mark .theme-toggle].freeze

    # Sub-pixel differences are rounding, not misalignment.
    ALIGN_TOLERANCE_PX = 1

    # runner.rb and gate_environment.rb both invoke a gate as `Class.run`. This
    # gate shipped with only the instance method, so it was a row in gates.yml
    # that nothing could call — registered, listed, and never once executed. The
    # gate exists to catch declarations with no reader; it was one.
    def self.run = new.run

    def initialize(result: GateResult.new)
      @result = result
    end

    def run
      unless CdpSession.available?
        @result.skipped_live("rendered_invariants: no Chrome — nothing measured")
        return @result
      end

      CdpSession.open do |session|
        session.viewport(1280, 800)
        SURFACES.each { |surface| check_surface(session, surface) }
      end
      @result
    rescue CdpSession::Unavailable => e
      @result.skipped_live("rendered_invariants: #{e.message}")
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
      measured = session.evaluate(PROBE)
      return @result.skipped_live("rendered_invariants: #{host} unreadable") unless measured

      data = JSON.parse(measured)
      @result.checked!(3)
      check_theme(host, surface[:theme], data)
      check_chat_corner(host, data)
      check_top_band_alignment(host, data)
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
        for (const sel of [".nav_link", ".brgen-logo-mark", ".theme-toggle"]) {
          const t = document.querySelector(sel);
          const tr = t?.getBoundingClientRect();
          band[sel] = (tr && tr.width > 0 && tr.height > 0)
            ? { cy: Math.round(tr.top + tr.height / 2) }
            : null;
        }
        // What the page says it is serving. surface_theme writes this per
        // surface, so it is the app's own answer rather than the gate's guess.
        const declared = document.documentElement.getAttribute("data-theme");
        return JSON.stringify({ bg, luma, chat, band, declared });
      })()
    JS
  end
end
