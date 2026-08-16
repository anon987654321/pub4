# frozen_string_literal: true
#
# Playback: play, loop, live and regenerate.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


# Stream / demo capture — WAV skips lame encode (faster than demo.mp3).
def stream_demo_path
  name = ENV.fetch("STREAM_DEMO", "demo.wav")
  name = "demo.wav" if name.empty?
  path = File.expand_path(name, OUTPUT_DIR)
  path = "#{path}.wav" unless path.match?(/\.(wav|mp3|flac|ogg|aiff?)\z/i)
  path
end

def stream_save_demo?
  return true if ENV["DILLA_STREAMING"] == "1"
  ENV.fetch("STREAM_SAVE_DEMO", "0") != "0"
end

def play(preset_name = nil, bars_count = 8)
  require_playback_tool!
  preset_name ||= "dilla"
  keep_demo = stream_save_demo?
  # WAV during stream: pcm_s16le only — no libmp3lame pass (faster cycle).
  out = keep_demo ? stream_demo_path : scratch_path("play_tmp.wav")
  prev = ENV["BARS"]
  ENV["BARS"] = bars_count.to_s
  attempts = play_render_attempts
  attempts.times do |try|
    pick_render_seed! if try.positive?
    if preset_name.to_s == "sketch"
      render(out)
    else
      ENV["TRACK"] = preset_name unless preset_name.to_s.empty? || preset_name == "dilla"
      render_dilla(out)
    end
    ok = if quality_gate_enabled?
           render_quality_acceptable?(out)
         elsif stream_iterate_enabled?
           stream_iterate_acceptable?(out)
         else
           true
         end
    break if ok
    dmesg_warn("render retry #{try + 1}/#{attempts}") if try + 1 < attempts
  end
  # Never let iterate/promote crashes skip speaker playback.
  begin
    stream_iterate_after_render!(out) if stream_iterate_enabled? && File.file?(out)
  rescue StandardError => e
    warn "stream iterate: #{e.class} — #{e.message} (still playing)"
  end
  begin
    log_render_meta(out) if quality_gate_enabled? || ENV["DILLA_STREAMING"] == "1"
  rescue StandardError => e
    warn "log_render_meta: #{e.message}"
  end
  if speech_over_track_enabled?
    cfg = dilla_resolve_config
    track_duration = (60.0 / cfg[:bpm]) * 4.0 * bars_count.to_i
    dmesg("speech overlay #{speech_tts_voice} rate=#{speech_tts_rate}", unit: "speech0", parent: "dilla0")
    speak_over_track!(out, track_duration, cfg[:bpm])
  end
  DillaDmesg.write!(out) if keep_demo && File.file?(out)
  play_audio(out)
ensure
  if defined?(prev)
    prev ? ENV["BARS"] = prev : ENV.delete("BARS")
  end
  FileUtils.rm_f(out) if defined?(out) && defined?(keep_demo) && !keep_demo
end

# Loop a WAV via ffplay (rb-only playback).
def play_loop(path)
  require_playback_tool!
  abort "missing #{path}" unless File.exist?(path)
  cfg = dilla_resolve_config
  prog = CHORD_PROGRESSIONS[cfg[:progression]]
  prog_names = prog.is_a?(Array) ? prog.join(" → ") : cfg[:progression].to_s
  dmesg("loop #{File.basename(path)} #{File.size(path)}B bpm=#{cfg[:bpm].to_i}", unit: "play0", parent: "dilla0")
  dmesg("progression #{prog_names}", unit: "harm0", parent: "dilla0")
  dmesg("ctrl-c to stop", unit: "play0", parent: "dilla0")
  play_audio(path, loop: true)
end

# Instant playback — cached WAV, no render wait.
def live_now
  harm = File.join(SCRATCH_DIR, "harmony_loud.wav")
  full = File.join(SCRATCH_DIR, "live_tmp.wav")
  path = File.exist?(harm) ? harm : full
  abort "no cache — run: ruby dilla.rb regenerate" unless File.exist?(path)
  play_loop(path)
end

# Harmony-forward stem mix from cached drum + harmonic renders.
def build_harmony_loud(
  drums: File.join(SCRATCH_DIR, "dilla_drums.wav"),
  harmonic: File.join(SCRATCH_DIR, "dilla_harmonic.wav"),
  out: File.join(SCRATCH_DIR, "harmony_loud.wav")
)
  abort "missing #{drums}" unless File.exist?(drums)
  abort "missing #{harmonic}" unless File.exist?(harmonic)
  dur = capture("ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1", harmonic).first.to_f
  dur = [dur, 8.0].max
  drum_vol = (ENV["DRUM_VOL"] || ENV["DRUM_MIX_WEIGHT"] || "0.38").to_f
  harm_gain = (ENV["HARM_VOL"] || "2.45").to_f
  harm_chain = "aformat=channel_layouts=stereo,lowpass=f=3200,aecho=0.35:0.4:120:0.32," \
               "volume=#{harm_gain},alimiter=limit=0.96:level_out=0.99"
  if drum_vol <= 0.001
    filt = "[0:a]#{harm_chain}[out]"
    sh! "ffmpeg", "-y", "-i", harmonic, "-filter_complex", filt,
        "-map", "[out]", "-t", dur.round(3).to_s, "-c:a", "pcm_s16le", out
    puts "wrote #{out} (#{dur.round(1)}s harmony-only, drums muted)"
  else
    filt = [
      "[1:a]#{harm_chain}[harm]",
      "[0:a]aformat=channel_layouts=stereo,volume=#{drum_vol}[drm]",
      "[drm][harm]amix=inputs=2:weights=1.0 1.0:duration=first:normalize=0[out]",
    ].join(";")
    sh! "ffmpeg", "-y", "-i", drums, "-i", harmonic, "-filter_complex", filt,
        "-map", "[out]", "-t", dur.round(3).to_s, "-c:a", "pcm_s16le", out
    puts "wrote #{out} (#{dur.round(1)}s harmony-forward, drums=#{drum_vol})"
  end
  out
end

# Fresh render + harmony-forward mix + ffplay loop.
def regenerate(bars_count = 16)
  require_tools! "ffmpeg"
  bars_count = (ENV["BARS"] || bars_count).to_i
  tmp = File.join(SCRATCH_DIR, "live_tmp.wav")
  harm = File.join(SCRATCH_DIR, "harmony_loud.wav")
  puts "regenerating #{bars_count} bars (TRACK=#{ENV['TRACK'] || 'timeless'})…"
  render_dilla(tmp, bars_count, keep_stems: true)
  build_harmony_loud
  puts "wrote #{tmp}"
  play_loop(harm)
end

# Chords + melody up front — loops .harmony_loud.wav.
def harmony_now
  harm = File.join(SCRATCH_DIR, "harmony_loud.wav")
  drums = File.join(SCRATCH_DIR, "dilla_drums.wav")
  harmonic = File.join(SCRATCH_DIR, "dilla_harmonic.wav")
  if ENV["REBUILD"] == "1" || !File.exist?(harm)
    if File.exist?(drums) && File.exist?(harmonic)
      build_harmony_loud
    else
      abort "no harmony mix — run: ruby dilla.rb regenerate"
    end
  end
  play_loop(harm)
end

# Loop full master — .live_tmp.wav via ffplay.
def live(bars_count = 32)
  tmp = File.join(SCRATCH_DIR, "live_tmp.wav")
  unless File.exist?(tmp)
    quick = [4, bars_count].min
    puts "no cache — warming #{quick} bars first (~15s)"
    render_dilla(tmp, quick)
    if bars_count > quick
      puts "rendering full #{bars_count} bars…"
      render_dilla(tmp, bars_count)
    end
  end
  play_loop(tmp)
rescue SystemCallError => e
  abort "playback failed: #{e.message}"
end
