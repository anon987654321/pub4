# frozen_string_literal: true
#
# The showcase demo and single-track stream playback.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


# Bare `ruby dilla.rb` (no args, no options) used to mean "continuous live
# stream" -- a `stream()` infinite loop needing afplay/ffplay to real
# speakers, which never terminates and can't run headless/over SSH. Sensible
# default instead: render a short demo.wav that actually showcases the
# engine's range (every named TRACK_PRESETS style, a few bars each,
# concatenated), matching "convention over configuration" -- no ENV knobs
# required to get a real, finite result. `ruby dilla.rb stream` still gives
# the old continuous behavior explicitly for anyone at a machine with speakers.
MEDLEY_DEFAULT_BARS = 4

def medley_styles
  list = if ENV["MEDLEY_STYLES"] && !ENV["MEDLEY_STYLES"].to_s.strip.empty?
           ENV["MEDLEY_STYLES"].split(",").map(&:strip).reject(&:empty?)
         else
           TRACK_PRESETS.keys.map(&:to_s)
         end
  limit = ENV["MEDLEY_LIMIT"]&.to_i
  limit && limit.positive? ? list.first(limit) : list
end

# Each style renders in its own subprocess (mirrors .all_tracks_demo/fill_holes.rb
# and stream()'s own exec-per-track pattern) -- dilla.rb mutates a lot of
# process-global ENV/state per render that isn't guaranteed to reset cleanly
# for a second render in the same process; a fresh interpreter per style sidesteps
# that entirely instead of auditing every mutation site for safety.
def showcase_demo!(dest = File.join(ROOT, "demo.wav"))
  bars = (ENV["MEDLEY_BARS"] || MEDLEY_DEFAULT_BARS.to_s).to_i.clamp(1, 64)
  styles = medley_styles
  dmesg("showcase: #{styles.length} styles x #{bars} bars -> #{File.basename(dest)}", unit: "demo0", parent: "dilla0")
  parts = []
  Dir.mktmpdir("dilla_medley") do |tmp|
    styles.each_with_index do |style, i|
      part = File.join(tmp, format("%03d_%s.wav", i, style))
      env = {
        "PATH" => ENV["PATH"], "HOME" => ENV["HOME"],
        "TMPDIR" => ENV["TMPDIR"], "TMP" => ENV["TMP"], "TEMP" => ENV["TEMP"],
        "GEM_HOME" => ENV["GEM_HOME"], "GEM_PATH" => ENV["GEM_PATH"],
        "BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"], "BUNDLE_PATH" => ENV["BUNDLE_PATH"],
        "RUBYOPT" => ENV["RUBYOPT"], "SSL_CERT_FILE" => ENV["SSL_CERT_FILE"],
        "SPEAK" => "0", "RAP_VOCAL" => "0", "CHOIR_VOX" => "0", "SELF_SAMPLE" => "0",
        "STREAM_CONTINUOUS" => "0", "DILLA_STREAMING" => "0",
        "TRACK" => style, "PROGRESSION" => style, "BARS" => bars.to_s,
      }.compact
      dmesg("showcase [#{i + 1}/#{styles.length}] #{style}", unit: "demo0", parent: "dilla0")
      rendered = false
      timed_out = false
      begin
        Timeout.timeout(ENV.fetch("MEDLEY_TRACK_TIMEOUT", "180").to_i) do
          # unsetenv_others: true -- without it Process.spawn (which Open3
          # delegates to) MERGES env onto the parent's inherited environment
          # rather than replacing it, so anything set for the outer showcase
          # invocation itself (BEAUTY_REPORT, MEDLEY_*, whatever a caller's
          # shell exported) leaks into what's supposed to be an isolated
          # child render. Same class of bug MASTER's own tts-worker spawn
          # path was hardened against.
          _out, status = Open3.capture2e(env, Gem.ruby, ENGINE_FILE, "dilla", part, bars.to_s,
                                          unsetenv_others: true)
          rendered = status.success? && File.file?(part) && File.size(part) > 50_000
        end
      rescue Timeout::Error
        timed_out = true
        dmesg_warn("showcase: #{style} timed out, skipping")
        system("pkill", "-9", "-f", "dilla.rb dilla .*#{Regexp.escape(part)}", out: File::NULL, err: File::NULL)
      end
      if rendered
        parts << part
      elsif !timed_out
        dmesg_warn("showcase: #{style} produced no usable audio, skipping")
      end
    end

    if parts.empty?
      dmesg_warn("showcase: no styles rendered successfully")
      return false
    end

    list_file = File.join(tmp, "concat.txt")
    File.write(list_file, parts.map { |p| "file #{Shellwords.escape(p)}" }.join("\n"))
    FileUtils.mkdir_p(File.dirname(dest))
    system("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list_file, "-c", "copy", dest,
           out: File::NULL, err: File::NULL)
  end
  ok = File.file?(dest) && File.size(dest) > 0
  dmesg(ok ? "showcase: wrote #{dest} (#{parts.length}/#{styles.length} styles)" : "showcase: failed", unit: "demo0", parent: "dilla0")
  ok
end

# A continuous techno set instead of the hip-hop rotation.
#
# The stream loop renders one track, plays it, moves to the next, forever. That
# is the right shape for a catalogue of progressions and the wrong one for a
# techno set, where the whole point is that it does not stop between pieces.
#
# STREAM_STYLE=techno routes each iteration through render_hate_techno instead,
# and advances a block counter across iterations so the set keeps evolving
# rather than restarting its arrangement every few minutes. Each pass renders a
# few minutes, plays them, and the next pass picks up further along the shape --
# the layer schedule reads a position from 0 to 1, so a stream that has been
# running for an hour is deep into the set rather than back at the intro.
#
# Blocks are rendered a few minutes at a time rather than in one long file so
# playback starts quickly and edits to the engine take effect within one block.
def stream_techno_enabled? = ENV["STREAM_STYLE"].to_s.downcase == "techno"

def stream_techno_block!(index)
  minutes = ENV.fetch("STREAM_TECHNO_MIN", "3").to_f.clamp(0.5, 20.0)
  # Walk the set: each block starts where the previous one left off, wrapping
  # after a full arc so an all-night stream keeps arriving somewhere.
  arc = ENV.fetch("STREAM_TECHNO_ARC", "6").to_i.clamp(2, 40)
  phase = index % arc
  dest = scratch_path("stream_techno_#{index % 2}.mp3")
  prev = ENV["HATE_PHASE"]
  ENV["HATE_PHASE"] = phase.to_s
  ENV["HATE_MIN"] = minutes.to_s
  begin
    dmesg("techno block #{index} — phase #{phase}/#{arc}, #{minutes} min @ #{HATE_BPM.round} BPM",
          unit: "stream0", parent: "dilla0")
    render_hate_techno(dest)
    play_audio(dest)
  ensure
    prev ? ENV["HATE_PHASE"] = prev : ENV.delete("HATE_PHASE")
  end
end

def stream_play_track!(bars_count)
  return stream_techno_block!(@stream_techno_index = (@stream_techno_index || -1) + 1) if stream_techno_enabled?

  timeout = stream_track_timeout_sec
  if timeout
    # play() renders, gates, iterates AND THEN blocks on play_audio for the full
    # length of the track, so wrapping all of it in the render budget meant the
    # budget was being spent on listening as well as working: a 32-bar track is
    # ~81s of playback on top of ~102s of render plus analysis, which overran
    # the 300s budget and killed the track mid-playback -- the stream would
    # start a track, cut it off partway, and log "timed out ... skipping".
    # Playback duration is known and is not work, so add it back; the budget
    # then means what its name says.
    cfg = dilla_resolve_config
    track_sec = (60.0 / cfg[:bpm].to_f) * 4.0 * bars_count.to_i
    Timeout.timeout(timeout + track_sec) { play("dilla", bars_count) }
  else
    play("dilla", bars_count)
  end
end
