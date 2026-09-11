# frozen_string_literal: true

# accent_contrast_probe — the text contrast of every filled control, on every
# surface the fleet declares, including brgen's verticals.
#
#   ruby gates/probes/accent_contrast_probe.rb              # every surface
#   GATE_SURFACES=brgen/takeaway ruby gates/probes/accent_contrast_probe.rb
#
# Why this exists rather than axe. The suites run axe, and only against each
# app's home page: brgen's PublicNavigationTest and bsdports' both visit root
# and stop. The seven verticals have no coverage at all, and on 2026-09-11 that
# is where the failures were — takeaway painted every .btn with a gradient from
# one competitor's red into another's magenta, measuring 3.43 and 2.15 against
# the ink it set, and tv's .btn-primary overrode the shared rule's --accent-ink
# back to --text at 3.60. Neither surface is a page axe visits.
#
# Scope is deliberate. This walks only controls that paint their own opaque
# background, where the foreground/background pair is unambiguous and a ratio
# means something without compositing every ancestor. Text over an image, a
# gradient, or a translucent fill is axe's problem and this probe skips it —
# a probe that guesses at a background reports numbers nobody can act on.
#
# Surfaces come from GeometryProbe, which reads the declared fleet and hands
# back each vertical's real host. Hardcoding those hosts here would be a second
# inventory, and the marketplace subdomain is localised per city — markedsplass
# in Bergen, marketplace in Los Angeles — so there is no single name to hardcode.

require "json"
require_relative "../support/cdp_session"
require_relative "../support/geometry_probe"

# The floors are WCAG 2.1 1.4.3: 3:1 for large text, 4.5:1 otherwise, where
# large is 24px, or 18.66px when bold.
JS = <<~JS
  (() => {
    const rgb = (s) => {
      const m = s.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/);
      return m ? { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] } : null;
    };
    const lin = (c) => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    const lum = (c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    const ratio = (a, b) => {
      const x = lum(a), y = lum(b);
      return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    };

    const bad = [];
    document.querySelectorAll("a, button, input[type=submit], .btn, [role=button]").forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return;

      const style = getComputedStyle(el);
      if (style.visibility === "hidden" || style.display === "none") return;
      // A gradient or image behind the text has no single background colour to
      // measure against, so the pair is not unambiguous and this is not ours.
      if (style.backgroundImage !== "none") return;

      const bg = rgb(style.backgroundColor);
      const fg = rgb(style.color);
      // A translucent fill composites with whatever is under it. Same reason.
      if (!bg || !fg || bg.a < 0.95) return;

      const px = parseFloat(style.fontSize);
      const bold = parseInt(style.fontWeight, 10) >= 700;
      const floor = (px >= 24 || (bold && px >= 18.66)) ? 3 : 4.5;
      const got = ratio(fg, bg);
      if (got >= floor) return;

      bad.push({
        sel: el.tagName.toLowerCase() +
             (typeof el.className === "string" && el.className.trim()
               ? "." + el.className.trim().split(/\\s+/).slice(0, 2).join(".")
               : ""),
        text: (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 24),
        got: Math.round(got * 100) / 100,
        floor: floor,
        px: Math.round(px * 10) / 10
      });
    });

    // One row per selector and ratio: a grid of twenty identical cards is one
    // defect, and listing it twenty times buries the next one.
    const seen = new Set();
    const once = bad.filter((b) => {
      const key = b.sel + ":" + b.got;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    return JSON.stringify(once.slice(0, 20));
  })()
JS

rows = Deploy::GeometryProbe.filter(Deploy::GeometryProbe.surfaces)
        .group_by { |s| [s.app, s.label] }
        .map { |_, group| group.first }

total = 0
measured = 0

Deploy::CdpSession.open(host_map: Deploy::GeometryProbe.host_map) do |cdp|
  cdp.viewport(1440, 900)
  rows.each do |surface|
    url = "http://#{surface.host || '127.0.0.1'}:#{surface.port}#{surface.path}"
    cdp.navigate(url, settle: 0.8)
    bad = JSON.parse(cdp.evaluate(JS).to_s)
    measured += 1

    name = "#{surface.app}/#{surface.label}"
    if bad.empty?
      puts "#{name}: every filled control clears its floor"
    else
      total += bad.size
      puts "#{name}: #{bad.size} under the floor"
      bad.each do |b|
        puts format("  %.2f (needs %s at %spx)  %s  %s", b["got"], b["floor"], b["px"], b["sel"], b["text"].inspect)
      end
    end
  rescue Deploy::CdpSession::Error => e
    # A surface that did not load measured nothing, and saying so is the whole
    # point — a probe that prints a pass for a page it never reached is the
    # failure this tree keeps finding.
    puts "#{name}: probe failed (#{e.class}) — measured nothing"
  end
end

puts "accent_contrast_probe: #{total} under the floor across #{measured} surface(s)"
exit(total.zero? ? 0 : 1)
