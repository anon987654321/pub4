#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true
#
# face_boot_smoke.rb [BASE_URL]
#
# Loads the MASTER chat face, dismisses the primer, and asserts the WebGL face
# actually BOOTS — window.MASTER_FACE is an object AND the canvas is drawing
# non-black pixels. Exit 0 = booted, 1 = still black/undefined.
#
# WHY: the rc.d assets gate only does STATIC assertions on face.runtime.js. It
# cannot catch a runtime loadFace() throw — a getter-only window.MASTER facade
# rejecting a legacy assignment, or a root-relative module specifier failing
# inside the blob: module. Those left the deployed face black on 2026-07-18 and
# nothing gated it. This is the missing runtime gate. Run it in CI or post-deploy
# where ferrum is available (BUNDLE_WITH=test), NOT in the prod bundle.
#
# Usage:
#   BUNDLE_WITH=test bundle34 exec ruby MASTER/web/script/face_boot_smoke.rb http://127.0.0.1:53187

require "ferrum"

BASE = ARGV[0] || ENV["MASTER_WEB_BASE"] || "http://127.0.0.1:53187"
TIMEOUT = Integer(ENV.fetch("FACE_SMOKE_TIMEOUT", "30"))

DISMISS_PRIMER = <<~JS
  (() => {
    try { if (typeof window.__MASTER_PRIMER_GO__ === 'function') window.__MASTER_PRIMER_GO__(); } catch (e) {}
    const p = document.getElementById('primer') || document.body;
    ['pointerdown', 'click', 'touchend'].forEach((t) => {
      try { p.dispatchEvent(new Event(t, { bubbles: true })); } catch (e) {}
    });
  })();
JS

PROBE = <<~JS
  (() => {
    const c = document.getElementById('face');
    const out = { face: typeof window.MASTER_FACE, profile: document.body.dataset.runtimeProfile };
    if (c) {
      out.w = c.width; out.h = c.height;
      try {
        const gl = c.getContext('webgl2') || c.getContext('webgl');
        const n = 16, px = new Uint8Array(4 * n * n);
        gl.readPixels((c.width >> 1) - n / 2, (c.height >> 1) - n / 2, n, n, gl.RGBA, gl.UNSIGNED_BYTE, px);
        let nb = 0; for (let i = 0; i < px.length; i += 4) { if (px[i] + px[i + 1] + px[i + 2] > 12) nb++; }
        out.nonBlack = nb;
      } catch (e) { out.pxErr = String(e); }
    }
    return out;
  })();
JS

browser = Ferrum::Browser.new(headless: true, timeout: TIMEOUT, process_timeout: TIMEOUT,
                              browser_options: { "no-sandbox" => nil })
detail = {}
booted = false
begin
  page = browser.create_page
  page.go_to("#{BASE}/?smoke=1")
  page.evaluate(DISMISS_PRIMER)

  deadline = Time.now + TIMEOUT
  until Time.now > deadline
    sleep 1.5
    detail = page.evaluate(PROBE) || {}
    if detail["face"] == "object" && detail["nonBlack"].to_i.positive?
      booted = true
      break
    end
  end
ensure
  browser.quit
end

if booted
  puts "face_boot_smoke: OK  MASTER_FACE=#{detail['face']} profile=#{detail['profile']} " \
       "nonBlack=#{detail['nonBlack']} canvas=#{detail['w']}x#{detail['h']}"
  exit 0
end

warn "face_boot_smoke: FAIL — face did not boot within #{TIMEOUT}s at #{BASE}"
warn "  last probe: #{detail.inspect}"
exit 1
