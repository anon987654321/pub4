# frozen_string_literal: true

# tap_target_probe — measure every interactive element's hit size against the
# design system's own --tap-min (44px), in a real mobile viewport over CDP.
#
# The 2026-08-17 debt entry found two under-minimum targets by hand; this is
# that check as an instrument, so the next one is found by running a script
# instead of by a thumb. Usage (triangle must be up):
#
#   ruby gates/probes/tap_target_probe.rb                 # default page set
#   ruby gates/probes/tap_target_probe.rb http://127.0.0.1:38182/posts
#
# An element under min in BOTH dimensions is reported; one squeezed in a
# single dimension inside a roomy row (a text link in prose) is WCAG-fine and
# skipped. display:none/zero-rect elements are invisible, not undersized.

require_relative "../support/cdp_session"

PAGES = {
  "brgen home" => "http://127.0.0.1:38182/",
  "brgen post feed" => "http://127.0.0.1:38182/posts",
  "marketplace" => "http://127.0.0.1:38182/?vertical=marketplace",
  "amber home" => "http://127.0.0.1:61352/",
  "amber items" => "http://127.0.0.1:61352/items",
  "bsdports home" => "http://127.0.0.1:47312/",
  "face" => "http://127.0.0.1:53187/",
}.freeze

JS = <<~JS
  (() => {
    const MIN = 44;
    const bad = [];
    const els = document.querySelectorAll("a, button, input, select, textarea, [role=button], [onclick], summary");
    for (const el of els) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      const style = getComputedStyle(el);
      if (style.visibility === "hidden" || style.display === "none") continue;
      // an element that cannot receive the tap is not a tap target — the
      // theme toggle input is a pointer-events:none proxy behind its label
      if (style.pointerEvents === "none") continue;
      // visually-hidden-until-focus (skip links): the clipped box is the HIDDEN
      // state, not a tap target
      if (style.position === "absolute" && (style.clipPath !== "none" || style.clip !== "auto" || r.right < 0 || r.bottom < 0)) continue;
      // a labelled control is tapped through its label — credit that area
      if (el.labels && el.labels.length) {
        const lr = el.labels[0].getBoundingClientRect();
        if (lr.width >= MIN || lr.height >= MIN) continue;
      }
      // prose links: an inline link inside a text block is exempt (WCAG 2.5.8)
      if (style.display === "inline" && el.tagName === "A" && el.closest("p, li, td, figcaption")) continue;
      if (r.width < MIN && r.height < MIN) {
        bad.push({
          sel: el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") +
               (el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\\s+/).slice(0,2).join(".") : ""),
          w: Math.round(r.width), h: Math.round(r.height),
          text: (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 30)
        });
      }
    }
    return JSON.stringify(bad.slice(0, 20));
  })()
JS

require "json"
pages = ARGV.empty? ? PAGES : { "arg" => ARGV.first }
total = 0
Deploy::CdpSession.open do |cdp|
  cdp.viewport(390, 844, mobile: true)
  pages.each do |name, url|
    cdp.navigate(url, settle: 0.6)
    bad = JSON.parse(cdp.evaluate(JS).to_s)
    if bad.empty?
      puts "#{name}: all tap targets >= 44px"
    else
      total += bad.size
      puts "#{name}: #{bad.size} under 44px"
      bad.each { |b| puts "  #{b['w']}x#{b['h']}  #{b['sel']}  #{b['text'].inspect}" }
    end
  rescue Deploy::CdpSession::Error => e
    puts "#{name}: probe failed (#{e.class}) — measured nothing"
  end
end
puts "tap_target_probe: #{total} undersized target(s) across #{pages.size} page(s)"
exit(total.zero? ? 0 : 1)
