#!/usr/bin/env ruby
# frozen_string_literal: true

# face_capture_probe — get the MASTER face on screen, so it can be recorded.
#
#   ruby gates/probes/face_capture_probe.rb                    # one still
#   ruby gates/probes/face_capture_probe.rb --frames 200       # a sequence
#   ruby gates/probes/face_capture_probe.rb --url http://127.0.0.1:53187/
#
# Why this exists: the face refuses to exist until someone taps it, so anything
# that records the page without tapping records the primer screen.
#
# It is worth being exact about the symptom, because the obvious guess is wrong.
# A capture that misses the face does not come back black -- the primer screen
# is dark but lit, and the sparse dot field is dark even when correct, so both
# look black at a glance and MEAN luminance rounds to zero for either. Measure
# max and percent-lit instead. The 131s loop.mp4 that this probe replaced was
# not black at all: frames 40 seconds apart were byte-identical at 1.15% lit,
# a single drawn frame held for the length of the video.
#
# index.html.erb line 34 is the whole story:
#
#     if (!window._primerFired && /webgl/i.test(String(type))) return null;
#
# getContext returns NULL for any WebGL request before the primer tap. THREE
# never initialises, the canvas stays empty, and a capture records the primer
# screen — which is near-black. DECISIONS.md calls that gate sacred, and it is
# in START_HERE's "do not optimize away" list, so the recorder is what has to
# change.
#
# Two things make the tap work here where a naive attempt does not.
#
#   1. The gate is a JS FLAG, not a browser policy. index.html.erb:34 tests
#      window._primerFired, and the page exposes its own opener at line 289 --
#      window.__MASTER_PRIMER_TAP__. So no trusted event is needed and calling
#      that function is the honest way in. (A keypress is kept as a fallback,
#      and Input.dispatchKeyEvent IS trusted, which matters for anything
#      gated on user activation -- audio -- but WebGL here is not.)
#
#   2. Headless Chrome has no GPU. Even once the gate lifts, context creation
#      fails without SwiftShader and the page sets __MASTER_RENDERER_FAILED__.
#      CdpSession takes webgl: true for exactly this.
#
# Readiness is dbgFrames, not a sleep. The page's own boot watchdog uses it
# (index.html.erb:285) and its comment says why: dbgFrames only increments from
# inside a real render loop, so it distinguishes "drew something" from "loaded
# and sat there". A timer cannot tell those apart, and a black frame is exactly
# what a timer would have captured.

require "fileutils"
require "json"
require "optparse"
require_relative "../support/cdp_session"
require_relative "../support/fleet"

options = { url: nil, frames: 1, out: "tmp/face_capture", interval: 0.04, timeout: 30 }
OptionParser.new do |o|
  o.banner = "usage: face_capture_probe.rb [--url URL] [--frames N] [--out DIR]"
  o.on("--url URL", "Face URL (default: MASTER on the loopback)") { |v| options[:url] = v }
  o.on("--frames N", Integer, "How many stills to capture (default 1)") { |v| options[:frames] = v }
  o.on("--out DIR", "Where to write them") { |v| options[:out] = v }
  o.on("--interval S", Float, "Seconds between frames") { |v| options[:interval] = v }
  o.on("--timeout S", Integer, "Seconds to wait for the first drawn frame") { |v| options[:timeout] = v }
end.parse!

url = options[:url] || Fleet.local_urls.fetch("master")
FileUtils.mkdir_p(options[:out])

unless Deploy::CdpSession.available?
  abort "warn: no Chrome. #{Deploy::CdpSession.chrome_path.inspect}"
end

# webgl: true is not optional here. Everything below assumes a context can
# actually be created once the gate lifts.
Deploy::CdpSession.open(webgl: true, timeout: options[:timeout]) do |cdp|
  cdp.viewport(1280, 720)
  cdp.navigate(url, settle: 0.6)

  state = lambda do
    JSON.parse(cdp.evaluate(<<~JS).to_s) # scan: intentional — a CDP probe evaluates JavaScript by definition
      (function(){
        // window.MASTER_FACE, not window.face. Reading the wrong global gives
        // undefined for both fields, which reads as "no renderer, no frames" --
        // indistinguishable from the legitimate 2D path, so the probe called a
        // page that had drawn nothing a success.
        var f = window.MASTER_FACE;
        return JSON.stringify({
          present: !!f,
          primer: !!(window._primerFired || (f && f.primerFired)),
          failed: !!window.__MASTER_RENDERER_FAILED__,
          frames: (f && f.dbgFrames) || 0,
          renderer: !!(f && f.renderer)
        });
      })()
    JS
  rescue StandardError
    {}
  end

  before = state.call
  puts "before tap: primer=#{before['primer']} frames=#{before['frames']}"

  # The tap.
  #
  # The WebGL gate is a plain JS flag -- index.html.erb:34 tests
  # window._primerFired -- not a browser user-activation policy. It therefore
  # needs no trusted event, and the page exposes its own entry point at line
  # 289: window.__MASTER_PRIMER_TAP__. Calling that is the honest way in.
  #
  # The keypress stays as a fallback: a build without that global still listens
  # for keydown (index.html.erb:305, :309), and Input.dispatchKeyEvent IS
  # trusted, which matters for anything genuinely gated on user activation --
  # audio, for one -- even though WebGL here is not.
  tapped = cdp.evaluate(<<~JS).to_s # scan: intentional — a CDP probe evaluates JavaScript by definition
    (function(){
      var go = window.__MASTER_PRIMER_TAP__ || window.__MASTER_PRIMER_GO__;
      if (typeof go === "function") { go(); return "called"; }
      return "absent";
    })()
  JS
  cdp.press("Enter") unless tapped.include?("called")
  puts "tap: #{tapped.include?(%q{called}) ? %q{__MASTER_PRIMER_TAP__()} : %q{keydown fallback}}"

  deadline = Time.now + options[:timeout]
  ready = nil
  loop do
    ready = state.call
    break if ready["failed"]
    # Wait for MASTER_FACE to EXIST before judging anything about it.
    #
    # This read `primer && (frames > 0 || !renderer)`, and on a surface with
    # data-primer="auto" the primer has already fired before the first poll
    # while the runtime is still loading. MASTER_FACE is undefined then, so
    # renderer is false, so !renderer is true, so the loop broke on iteration
    # one -- and the guard below aborted saying the runtime never loaded. The
    # probe refused a face that was seconds from drawing.
    #
    # The !renderer clause exists to accept the 2D path, which is a real
    # outcome: face.part1.txt sets "2d mode" when WebGL is absent. But
    # "no renderer" and "no runtime yet" both report renderer=false, and only
    # `present` separates them.
    break if ready["present"] && ready["primer"] &&
             (ready["frames"].to_i.positive? || !ready["renderer"])
    break if Time.now > deadline

    sleep 0.1
  end

  if ready["failed"]
    abort "warn: __MASTER_RENDERER_FAILED__ — the page gave up on the renderer after the tap"
  end
  unless ready["primer"]
    abort "warn: primer never fired. The tap was not accepted; the face is still gated."
  end
  unless ready["present"]
    abort "warn: window.MASTER_FACE is undefined — the face runtime never loaded. " \
          "Nothing has drawn; a capture here would be black."
  end
  if ready["frames"].to_i.zero? && ready["renderer"]
    abort "warn: primer fired and a renderer exists but dbgFrames is 0 — loaded, never drew. " \
          "This is the black-capture case; do not record it."
  end

  puts "after tap:  primer=#{ready['primer']} frames=#{ready['frames']} renderer=#{ready['renderer']}"

  options[:frames].times do |i|
    path = File.join(options[:out], format("face_%04d.png", i))
    cdp.screenshot(path)
    sleep options[:interval] if options[:frames] > 1
  end

  after = state.call
  drawn = after["frames"].to_i - ready["frames"].to_i
  puts "captured #{options[:frames]} frame(s) -> #{options[:out]}"
  # A sequence whose frame counter did not move is a still repeated N times,
  # which looks like footage and is not. Said rather than left to be noticed in
  # the edit.
  if options[:frames] > 1 && drawn <= 0
    warn "warn: dbgFrames did not advance during capture — every frame is identical"
  else
    puts "face advanced #{drawn} frame(s) while capturing"
  end
end
