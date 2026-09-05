# frozen_string_literal: true

# focus_walk_probe — tab through a page and demand every stop shows a ring.
#
# The fleet's focus contract is _focus_ring.scss: a visible outline on
# :focus-visible, guaranteed with the one sanctioned !important. This walks
# that contract the way a keyboard user does — Tab, look, Tab, look — instead
# of trusting that the CSS reaches every component. A stop with outline:none
# and no border/background change is a place a keyboard user is lost.
#
#   ruby gates/probes/focus_walk_probe.rb                    # default pages
#   ruby gates/probes/focus_walk_probe.rb <url> [steps]

require_relative "../support/cdp_session"
require_relative "../support/fleet"
require "json"

PAGES = Fleet.urls({
  # Routes, not numbers -- see the note in tap_target_probe.
  "brgen home" => %w[brgen /],
  "amber home" => %w[amber /],
  "bsdports home" => %w[bsdports /],
  "face" => %w[master /],
}).freeze

CHECK = <<~JS
  (() => {
    const el = document.activeElement;
    if (!el || el === document.body) return JSON.stringify({done: true});
    const cs = getComputedStyle(el);
    const before = getComputedStyle(el, "::before");
    const ring = (cs.outlineStyle !== "none" && parseFloat(cs.outlineWidth) > 0) ||
                 cs.boxShadow !== "none" ||
                 (before.outlineStyle !== "none" && parseFloat(before.outlineWidth) > 0);
    return JSON.stringify({
      sel: el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") +
           (typeof el.className === "string" && el.className ? "." + el.className.trim().split(/\\s+/)[0] : ""),
      ring: ring,
      text: (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 25)
    });
  })()
JS

pages = ARGV.empty? ? PAGES : { "arg" => ARGV.first }
steps = (ARGV[1] || 25).to_i
total_bad = 0

Deploy::CdpSession.open do |cdp|
  cdp.viewport(390, 844, mobile: true)
  pages.each do |name, url|
    cdp.navigate(url, settle: 0.6)
    bad = []
    seen = []
    steps.times do
      cdp.press("Tab")
      state = JSON.parse(cdp.evaluate(CHECK).to_s)
      break if state["done"]
      key = state["sel"]
      break if seen.include?(key) && seen.last(3).include?(key) # cycled
      seen << key
      bad << "#{key} #{state['text'].inspect}" unless state["ring"]
    end
    bad.uniq!
    total_bad += bad.size
    puts bad.empty? ? "#{name}: #{seen.uniq.size} stops, every one shows a ring" :
                      "#{name}: #{bad.size} ringless stop(s) of #{seen.uniq.size}"
    bad.first(8).each { |b| puts "  #{b}" }
  rescue Deploy::CdpSession::Error => e
    puts "#{name}: probe failed (#{e.class}) — measured nothing"
  end
end
puts "focus_walk_probe: #{total_bad} ringless stop(s)"
exit(total_bad.zero? ? 0 : 1)
