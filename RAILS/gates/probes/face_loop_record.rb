#!/usr/bin/env ruby
# frozen_string_literal: true

# face_loop_record — record the MASTER face speaking a wav, frame by frame.
#
#   ruby gates/probes/face_loop_record.rb --audio ../MASTER/tts.wav \
#        --out ../MASTER/loop.mp4 --fps 20 --clip 440,90,400,540
#
# The companion to face_capture_probe, which exists to get the face on screen;
# this one records it, in sync with audio, and muxes the audio back in.
#
# Three things make the sync exact, and none of them is a sleep.
#
#   1. The mouth is driven by the wav, not by playback. The face reads
#      tts.analyser every frame (face.part3.txt:262) for an RMS and three band
#      energies, so this precomputes both buffers per video frame from the wav
#      itself and installs an analyser that answers from that table. Headless
#      Chrome has no audio device; nothing here needs one.
#   2. The animation clock is ours. requestAnimationFrame is stubbed after the
#      first drawn frame and MASTER_FACE.frame(t) is called with the video's own
#      timestamps, so one captured frame is exactly one 1/fps step of face time.
#      Left to real time, capture runs slower than playback and the face idles in
#      slow motion under a voice at full speed.
#   3. The crop is Chrome's, through captureScreenshot's clip. Cropping in ffmpeg
#      afterwards costs a full-frame encode of pixels nobody sees.
#
# It records what the face looks like, and nothing more. --tint and --exposure
# can pin uColor and uExposure, and both default to zero, which leaves the page
# alone: a take that has to be lit by its recorder is a take of something no
# visitor will ever see. The first version of this file lit the face because the
# face was drawn at a fifth of the light it needed; that was fixed where it
# belonged, in face.part2.txt's depth shade and face.part3.txt's INK.
#
# Pinning, when it is asked for, is a defineProperty rather than an assignment:
# every uniform is rewritten from State on every frame, so a plain assignment
# lasts exactly one frame.

require "base64"
require "fileutils"
require "json"
require "optparse"
require_relative "../support/cdp_session"
require_relative "../support/fleet"

options = {
  url: nil, audio: nil, out: nil, fps: 20, seconds: nil, clip: nil,
  work: nil, exposure: 0.0, tint: 0.0, timeout: 40, viewport: [1280, 720], scale: 2, warmup: 20, crf: 28,
}
OptionParser.new do |o|
  o.banner = "usage: face_loop_record.rb --audio WAV --out MP4 [options]"
  o.on("--url URL", "Face URL (default: MASTER on the loopback)") { |v| options[:url] = v }
  o.on("--audio PATH", "16-bit PCM wav to speak") { |v| options[:audio] = v }
  o.on("--out PATH", "mp4 to write") { |v| options[:out] = v }
  o.on("--fps N", Integer, "Video frame rate (default 20)") { |v| options[:fps] = v }
  o.on("--seconds N", Float, "Record only the first N seconds") { |v| options[:seconds] = v }
  o.on("--clip X,Y,W,H", "Crop, in CSS pixels") { |v| options[:clip] = v.split(",").map(&:to_i) }
  o.on("--work DIR", "Where frames go (default: a temp dir under the audio)") { |v| options[:work] = v }
  o.on("--exposure F", Float, "Pin uExposure to this; 0 leaves the page's own") { |v| options[:exposure] = v }
  o.on("--tint F", Float, "Pin uColor to this grey; 0 leaves the page's own") { |v| options[:tint] = v }
  o.on("--timeout S", Integer, "Seconds to wait for the first drawn frame") { |v| options[:timeout] = v }
  o.on("--viewport WxH", "Page size in CSS pixels (default 1280x720)") { |v| options[:viewport] = v.split("x").map(&:to_i) }
  o.on("--scale F", Float, "Device pixel ratio for the capture (default 2)") { |v| options[:scale] = v }
  o.on("--from N", Integer, "First frame of this slice (default 0)") { |v| options[:from] = v }
  o.on("--to N", Integer, "One past the last frame of this slice (default: all)") { |v| options[:to] = v }
  o.on("--warmup N", Integer, "Frames drawn and dropped before the first kept one (default 20)") { |v| options[:warmup] = v }
  o.on("--crf N", Integer, "x264 quality, lower is bigger (default 28)") { |v| options[:crf] = v }
end.parse!

abort "usage: --audio WAV --out MP4" unless options[:audio] && options[:out]
abort "no such wav: #{options[:audio]}" unless File.file?(options[:audio])

FFT_SIZE = 256          # analyser.fftSize in face_speech_runtime.js:590
BINS = FFT_SIZE / 2     # analyser.frequencyBinCount
FRAME_BYTES = FFT_SIZE + BINS
MIN_DB = -100.0         # AnalyserNode defaults, which is what the face reads
MAX_DB = -30.0

# --- the wav -----------------------------------------------------------------

# Minimal RIFF read: enough for a mono or stereo 16-bit PCM file, which is what
# ffmpeg writes here and all the face needs. Anything else is refused rather than
# silently misread as noise.
def read_wav(path)
  raw = File.binread(path)
  raise "not a RIFF/WAVE file: #{path}" unless raw[0, 4] == "RIFF" && raw[8, 4] == "WAVE"

  offset = 12
  fmt = nil
  data = nil
  while offset + 8 <= raw.bytesize
    id = raw[offset, 4]
    size = raw[offset + 4, 4].unpack1("V")
    body = raw[offset + 8, size]
    fmt = body.unpack("vvVVvv") if id == "fmt "
    data = body if id == "data"
    offset += 8 + size + (size.odd? ? 1 : 0)
  end
  raise "no fmt/data chunk in #{path}" unless fmt && data

  format, channels, rate, _bytes_s, _align, bits = fmt
  raise "expected 16-bit PCM, got format #{format} at #{bits} bits" unless format == 1 && bits == 16

  samples = data.unpack("s<*")
  samples = samples.each_slice(channels).map { |frame| frame.sum / channels } if channels > 1
  [samples, rate]
end

# One radix-2 FFT, in place, on parallel real/imaginary arrays. Small enough to
# state here; pulling in a gem for a 256-point transform is a dependency for
# thirty lines.
def fft!(re, im)
  n = re.size
  j = 0
  (1...n).each do |i|
    bit = n >> 1
    while j & bit != 0
      j ^= bit
      bit >>= 1
    end
    j |= bit
    if i < j
      re[i], re[j] = re[j], re[i]
      im[i], im[j] = im[j], im[i]
    end
  end
  len = 2
  while len <= n
    angle = -2.0 * Math::PI / len
    wr = Math.cos(angle)
    wi = Math.sin(angle)
    (0...n).step(len) do |start|
      cr = 1.0
      ci = 0.0
      (0...(len / 2)).each do |k|
        a = start + k
        b = a + len / 2
        tr = re[b] * cr - im[b] * ci
        ti = re[b] * ci + im[b] * cr
        re[b] = re[a] - tr
        im[b] = im[a] - ti
        re[a] += tr
        im[a] += ti
        cr, ci = (cr * wr - ci * wi), (cr * wi + ci * wr)
      end
    end
    len <<= 1
  end
end

HANN = Array.new(FFT_SIZE) { |i| 0.5 - (0.5 * Math.cos(2.0 * Math::PI * i / (FFT_SIZE - 1))) }.freeze

# Per video frame: the time-domain bytes the face takes an RMS from, and the
# frequency bytes it splits into bass, mids and highs — in the units
# getByteTimeDomainData and getByteFrequencyData return, because that is what
# the face's own arithmetic assumes.
def envelope(samples, rate, frames, fps)
  out = String.new(capacity: frames * FRAME_BYTES, encoding: Encoding::BINARY)
  re = Array.new(FFT_SIZE, 0.0)
  im = Array.new(FFT_SIZE, 0.0)
  span = MAX_DB - MIN_DB

  frames.times do |index|
    start = (index * rate / fps.to_f).round
    time_bytes = Array.new(FFT_SIZE) do |i|
      sample = samples[start + i] || 0
      [[((sample / 32_768.0) * 128.0).round + 128, 0].max, 255].min
    end
    FFT_SIZE.times do |i|
      re[i] = ((samples[start + i] || 0) / 32_768.0) * HANN[i]
      im[i] = 0.0
    end
    fft!(re, im)
    freq_bytes = Array.new(BINS) do |k|
      magnitude = Math.sqrt((re[k] * re[k]) + (im[k] * im[k])) / (FFT_SIZE / 2.0)
      db = magnitude.positive? ? 20.0 * Math.log10(magnitude) : MIN_DB
      byte = ((db - MIN_DB) / span * 255.0).round
      [[byte, 0].max, 255].min
    end
    out << time_bytes.pack("C*") << freq_bytes.pack("C*")
  end
  out
end

samples, rate = read_wav(options[:audio])
duration = samples.size / rate.to_f
duration = [duration, options[:seconds]].min if options[:seconds]
frames = (duration * options[:fps]).floor
abort "audio is #{duration.round(2)}s — nothing to record" if frames < 2

work = options[:work] || File.join(File.dirname(File.expand_path(options[:out])), "loop_frames")
FileUtils.mkdir_p(work)

frame_path = ->(index) { File.join(work, format("f_%05d.jpg", index)) }

# Resumable, and meant to be run in chunks. A browser holding four minutes of
# this face grows until the machine complains — the pools, ghosts and mood
# history are all per-session — so one run takes a slice, and the next takes the
# next slice in a fresh browser. A frame already on disk is never recaptured.
from = options[:from] || 0
to = [options[:to] || frames, frames].min
pending = (from...to).reject { |index| File.size?(frame_path.call(index)) }

puts "audio #{File.basename(options[:audio])}: #{duration.round(2)}s at #{rate}Hz -> #{frames} frames at #{options[:fps]}fps"
puts "slice #{from}...#{to}: #{pending.size} to capture, #{(to - from) - pending.size} already on disk"

# The page fetches the table rather than being handed it: two megabytes through
# Runtime.evaluate is a two-megabyte JavaScript string to parse.
public_dir = File.expand_path("../../../MASTER/web/public", __dir__)
abort "no MASTER/web/public at #{public_dir}" unless File.directory?(public_dir)

envelope_path = File.join(public_dir, "loop_envelope.bin")
if File.size?(envelope_path).to_i == frames * FRAME_BYTES
  puts "envelope: reusing #{File.size(envelope_path)} bytes from a previous slice"
else
  File.binwrite(envelope_path, envelope(samples, rate, frames, options[:fps]))
  puts "envelope: #{File.size(envelope_path)} bytes -> #{envelope_path}"
end

url = options[:url] || Fleet.local_urls.fetch("master")
abort "warn: no Chrome. #{Deploy::CdpSession.chrome_path.inspect}" unless Deploy::CdpSession.available?

begin
  Deploy::CdpSession.open(webgl: true, timeout: options[:timeout]) do |cdp|
    width, height = options[:viewport]
    cdp.viewport(width, height, scale: options[:scale])
    cdp.navigate(url, settle: 0.8)

    # The primer gate: index.html.erb returns null for a WebGL context until
    # window._primerFired, and the page exposes its own opener. face_capture_probe
    # records why this is the honest way in rather than a synthetic tap.
    cdp.evaluate(<<~JS) # scan: intentional — a CDP recorder evaluates JavaScript by definition
      (function(){
        var go = window.__MASTER_PRIMER_TAP__ || window.__MASTER_PRIMER_GO__;
        if (typeof go === "function") { go(); return "called"; }
        return "absent";
      })()
    JS

    # dbgFrames, not a sleep: it only increments inside a real render loop, so it
    # separates "drew something" from "loaded and sat there".
    deadline = Time.now + options[:timeout]
    ready = nil
    loop do
      ready = JSON.parse(cdp.evaluate(<<~JS).to_s) # scan: intentional — a CDP recorder evaluates JavaScript by definition
        JSON.stringify({
          present: !!window.MASTER_FACE,
          frames: (window.MASTER_FACE && window.MASTER_FACE.dbgFrames) || 0,
          mat: !!(window.MASTER_FACE && window.MASTER_FACE.faceMat),
          failed: !!window.__MASTER_RENDERER_FAILED__
        })
      JS
      break if ready["failed"] || (ready["present"] && ready["frames"].to_i > 2 && ready["mat"])
      break if Time.now > deadline

      sleep 0.15
    end
    abort "warn: __MASTER_RENDERER_FAILED__ — the page gave up on the renderer" if ready["failed"]
    abort "warn: the face never drew (frames=#{ready['frames']}, faceMat=#{ready['mat']})" unless
      ready["present"] && ready["frames"].to_i > 2 && ready["mat"]

    puts "face drew #{ready['frames']} frames before capture"

    installed = cdp.evaluate(<<~JS, await_promise: true) # scan: intentional — a CDP recorder evaluates JavaScript by definition
      (async function(){
        const F = window.MASTER_FACE;
        const buf = new Uint8Array(await (await fetch('/loop_envelope.bin')).arrayBuffer());
        const FRAME_BYTES = #{FRAME_BYTES}, FFT = #{FFT_SIZE}, BINS = #{BINS};
        window.__LOOP = { buf, frame: 0, frames: #{frames} };

        // The face asks for both buffers every frame and takes an RMS and three
        // band sums off them. Answering from the table is what makes the mouth
        // the wav's mouth.
        const tts = F.tts;
        tts.playing = true;
        tts.analyserBuf = new Uint8Array(FFT);
        tts.analyserFreqBuf = new Uint8Array(BINS);
        tts.analyser = {
          getByteTimeDomainData(out) {
            const at = window.__LOOP.frame * FRAME_BYTES;
            out.set(buf.subarray(at, at + FFT));
          },
          getByteFrequencyData(out) {
            const at = (window.__LOOP.frame * FRAME_BYTES) + FFT;
            out.set(buf.subarray(at, at + BINS));
          }
        };

        // Pinned, not assigned: every uniform is rewritten from State each frame.
        const mat = F.faceMat;
        const pin = (name, value) => {
          const u = mat.uniforms[name];
          if (!u) return false;
          Object.defineProperty(u, 'value', { get: () => value, set: () => {}, configurable: true });
          return true;
        };
        // Zero leaves the page alone, and zero is the default: the face is drawn
        // at the brightness it should have (part2's shade floor and part3's INK),
        // so a recorder has no business deciding how MASTER looks. A take that
        // has to be lit by its recorder is recording something the visitor will
        // never see.
        const tintValue = #{options[:tint]};
        if (tintValue > 0) {
          const tint = mat.uniforms.uColor.value;
          tint.setRGB(tintValue, tintValue, tintValue);
          tint.copy = () => tint;
          tint.lerp = () => tint;
        }
        const exposureValue = #{options[:exposure]};
        const exposure = exposureValue > 0 ? pin('uExposure', exposureValue) : false;

        // Ours from here: the natural loop would advance face time by wall clock
        // while capture runs slower than playback.
        window.requestAnimationFrame = () => 0;
        return JSON.stringify({ bytes: buf.length, exposure });
      })()
    JS
    puts "installed: #{installed}"

    step = 1000.0 / options[:fps]
    clip = options[:clip]
    clip_params = clip ? { x: clip[0], y: clip[1], width: clip[2], height: clip[3], scale: 1 } : nil
    started = Time.now

    # frame() clamps its own delta at 50ms (66 on a coarse pointer), so a step
    # larger than that advances every spring and lerp by less than the video
    # advances: at 10fps the oscillators, which read t directly, would run at
    # full speed while the morph spring, the colour lerp and the bass average ran
    # at half. The face drifts out of time with its own voice, subtly enough to
    # look like bad animation rather than a bug. So a video frame is drawn in as
    # many 50ms steps as it takes, and only the last one is kept.
    SUBSTEP_MS = 50.0
    substeps = [(step / SUBSTEP_MS).ceil, 1].max

    # A frame of face time, drawn. The oscillators are functions of t so they
    # carry across a chunk boundary on their own, but the springs — morph,
    # colour, the bass average — start from rest in a fresh browser, so the
    # first frames of a slice are drawn and thrown away rather than kept.
    render = lambda do |index|
      base = index * step
      times = (1..substeps).map { |n| (base - step + (step * n / substeps)).round(3) }
      cdp.evaluate(<<~JS) # scan: intentional — a CDP recorder evaluates JavaScript by definition
        (function(){
          window.__LOOP.frame = #{index};
          const F = window.MASTER_FACE;
          F.tts.playing = true;
          // A conversation IS interaction, and so is a four-minute utterance.
          // sendMessage resets lastTouch for exactly this reason
          // (face.part5.txt:790): past sixty seconds without it, frame() drifts
          // morphTarget down to 0.55 and the face gathers into a dim oval
          // halfway through the take.
          F.State.lastTouch = #{base.round(3)};
          #{times.map { |t| "F.frame(#{t});" }.join("\n          ")}
          return 1;
        })()
      JS
    end

    warmup = options[:warmup]
    first = pending.first
    [warmup, first].min.times { |back| render.call(first - [warmup, first].min + back) } if first

    pending.each_with_index do |index, done|
      render.call(index)
      cdp.screenshot(frame_path.call(index), format: "jpeg", quality: 88, clip: clip_params)

      next unless ((done + 1) % 200).zero?

      rate_now = (done + 1) / (Time.now - started)
      puts format("  %d/%d of the slice  %.1f fps capture  eta %.0fs",
                  done + 1, pending.size, rate_now, (pending.size - done - 1) / rate_now)
    end

    puts "captured #{pending.size} frames in #{(Time.now - started).round}s"
  end
end

# The encode waits for the whole take. A slice run leaves the frames it captured
# and says what is still missing, so the next slice picks up from there.
missing = (0...frames).reject { |index| File.size?(frame_path.call(index)) }
unless missing.empty?
  # The envelope stays for the next slice; it is deleted with the last one.
  puts "#{missing.size} frames still missing, first at #{missing.first} — rerun with --from #{missing.first}"
  exit 0
end
FileUtils.rm_f(envelope_path)

# One encode: the frames at their own rate, the wav beside them, nothing scaled
# or cropped a second time. yuv420p and faststart because this is played in a
# browser and a README.
audio_args = ["-i", options[:audio], "-c:a", "aac", "-b:a", "128k", "-shortest"]
ok = system("ffmpeg", "-y", "-loglevel", "error",
            "-framerate", options[:fps].to_s, "-i", File.join(work, "f_%05d.jpg"),
            *audio_args,
            "-c:v", "libx264", "-preset", "slow", "-crf", options[:crf].to_s,
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            options[:out])
abort "ffmpeg failed" unless ok && File.size?(options[:out])

puts "wrote #{options[:out]} (#{File.size(options[:out])} bytes)"
puts "frames kept at #{work} — delete them once the take is approved"
