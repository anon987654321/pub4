# frozen_string_literal: true
#
# The Madlib and Slum Village renderers.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.


# =============================================================================
# MADLIB DRUMS — pure dirty MPC beats, Dilla-time, no harmony/stems
# =============================================================================

def delicious_pocket_enabled?
  ENV.fetch("DELICIOUS", "1") !~ /\A(?:0|false|off)\z/i
end

def vlc_effects_enabled?
  ENV.fetch("VLC", "1") !~ /\A(?:0|false|off)\z/i
end

def madlib_resolve_config
  cfg = dilla_resolve_config
  base_timing = MICROTIMING_MS.merge(cfg[:timing] || {})
  timing = LOOSE_POCKET_TIMING_MS.merge(base_timing) { |_k, mad, base| base || mad }
  swing = (ENV["SWING"] || [cfg[:swing] + 6, 68].min).to_f
  bpm = cfg[:bpm]
  if delicious_pocket_enabled?
    ratio = (ENV["DELICIOUS_RATIO"] || DELICIOUS_POCKET_RATIO).to_f
    bpm = (bpm * ratio).round(1)
    swing = [swing + 4, 72].min
    timing = timing.merge(snare: -32..-14, hat_up: 26..44, kick_sync: 14..28)
  end
  cfg.merge(feel: :loose_pocket, swing:, timing:, bpm:, delicious: delicious_pocket_enabled?)
end

def vlc_eq_chain
  VLC_EQ_BANDS.map { |f, g| "equalizer=f=#{f}:t=o:w=1:g=#{g}" }.join(",")
end

# VLC audio effects chain — loudnorm, 10-band EQ, compressor, spatializer, stereo widener.
def vlc_audio_filters(input_tag, out_tag: "out")
  return ["[#{input_tag}]alimiter=limit=0.91:level_out=0.92[#{out_tag}]"] unless vlc_effects_enabled?
  c = VLC_COMPRESSOR
  eq = vlc_eq_chain
  [
    "[#{input_tag}]#{eq}[veq]",
    "[veq]acompressor=threshold=#{c[:threshold]}dB:ratio=#{c[:ratio]}:attack=#{c[:attack]}:release=#{c[:release]}:" \
    "makeup=#{c[:makeup]}:mix=#{c[:mix]}[vcomp]",
    "[vcomp]aphaser=in_gain=0.42:out_gain=0.72:delay=3:decay=0.28:speed=0.35:type=triangular[vph]",
    "[vph]aecho=0.38:0.42:38|76|114:0.22|0.14|0.08[vspat]",
    "[vspat]extrastereo=m=1.30[vwide]",
    "[vwide]stereotools=mode=lr>ms:slev=1.22:mlev=0.90[vms]",
    "[vms]stereotools=mode=ms>lr:base=0.16[vst]",
    "[vst]alimiter=limit=0.94:level_out=0.93[#{out_tag}]",
  ]
end

def madlib_drum_filters(input_tag = "bed", out_tag: "mad_out")
  sat = Math.tanh(2.6).round(6)
  [
    "[#{input_tag}]asplit=2[md][sc]",
    "[md]acrusher=bits=10:samples=1.69:mix=0.55[cr]",
    "[cr]aeval=exprs='tanh(2.6*val(0))/#{sat}|tanh(2.6*val(1))/#{sat}'[sat]",
    "[sat]acompressor=threshold=-17dB:ratio=8:attack=2:release=65:makeup=5.5[comp]",
    "[comp]equalizer=f=55:t=o:w=0.75:g=7,equalizer=f=2400:t=o:w=2:g=-5,equalizer=f=9000:t=o:w=2:g=-3[eq]",
    "[eq]extrastereo=m=1.14[wide]",
    "[wide][sc]sidechaincompress=threshold=-19dB:ratio=7:attack=1:release=75:level_sc=0.85[punched]",
    "[punched]vibrato=f=0.22:d=0.005[wow]",
    "[wow]aeval=exprs='val(0)+0.014*(random(0)-0.5)|val(1)+0.014*(random(1)-0.5)'[#{out_tag}]",
  ]
end

def madlib_master_filters(input_tag = "bed")
  filt = []
  filt.concat(madlib_drum_filters(input_tag, out_tag: "mad_out"))
  filt.concat(vlc_audio_filters("mad_out"))
  filt
end

# Pure drums: MPC one-shots + pocket microtiming + SP-1200 dirt.
def render_madlib_drums(destination = File.join(ROOT, "renders", "beats", "beat.wav"), bars_count = nil)
  require_tools! "ffmpeg"
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  cfg      = madlib_resolve_config
  n_bars   = bars_count || (ENV["BARS"] ? bars : 32)
  beat_p   = 60.0 / cfg[:bpm]
  duration = (beat_p * 4.0 * n_bars).round(3)
  events   = dilla_schedule(
    n_bars, beat_p, [], drums_only: true,
    swing: cfg[:swing], feel: :loose_pocket, timing: cfg[:timing]
  )
  kit = {
    kick: load_mono_sample(drum_sample_path("kick.wav")),
    snare: load_mono_sample(drum_sample_path("snare.wav")),
    ghost: load_mono_sample(drum_sample_path("ghost.wav")),
    hat: load_mono_sample(drum_sample_path("hat.wav")),
    open_hat: load_mono_sample(drum_sample_path("open_hat.wav")),
  }
  drum_tmp = File.join(SCRATCH_DIR, "madlib_drums.wav")
  render_sample_bus_wav(
    drum_tmp,
    events, duration, kit,
    kick: :kick, snare: :snare, ghost: :ghost, hat: :hat, open: :open_hat
  )

  command = ["ffmpeg", "-y", "-i", drum_tmp,
             "-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.028:d=#{duration}:seed=#{noise_seed(18)}"]
  filt = [
    "[0:a]aformat=channel_layouts=stereo[drums]",
    "[1:a]highpass=f=120,lowpass=f=9000,volume=0.22[dust]",
    "[drums][dust]amix=inputs=2:weights=1.0 0.35:duration=first[bed]",
  ]
  filt.concat(madlib_master_filters("bed"))
  ext = File.extname(destination).downcase
  args = ext == ".mp3" ? codec_for(destination) : ["-c:a", "pcm_s16le"]
  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *args, destination]
  sh!(*command)
  FileUtils.rm_f(drum_tmp)
  fx = []
  fx << "delicious" if cfg[:delicious]
  fx << "vlc-all" if vlc_effects_enabled?
  puts "wrote #{destination} (#{cfg[:bpm].to_i} BPM, #{n_bars} bars, TRACK=#{cfg[:track]}, #{fx.join('+')})"
end

def render_madlib_album(output_dir = File.join(ROOT, "renders", "beats"))
  FileUtils.mkdir_p(output_dir)
  LOOSE_POCKET_BEAT_CATALOG.each do |entry|
    base = File.join(output_dir, entry[:out])
    prev = %w[TRACK BARS BPM SWING DELICIOUS VLC].each_with_object({}) { |k, h| h[k] = ENV[k] }
    ENV["TRACK"] = entry[:track].to_s
    ENV["BARS"]  = entry[:bars].to_s
    ENV["DELICIOUS"] = "1"
    ENV["VLC"] = "1"
    render_madlib_drums("#{base}.wav", entry[:bars])
    render_madlib_drums("#{base}.mp3", entry[:bars])
  ensure
    prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
  puts "loose_pocket batch: #{LOOSE_POCKET_BEAT_CATALOG.length} beats (wav+mp3) → #{output_dir}"
end

# =============================================================================
# HIP-HOP SYNTH (dilla_hiphop.rb)
# =============================================================================

# Batch-render tape presets — neutral session_XX filenames (no album track names).
def render_slum_album(output_dir = File.join(ROOT, "renders"))
  FileUtils.mkdir_p(output_dir)
  TAPE_RENDER_CATALOG.each_with_index do |entry, i|
    dest = File.join(output_dir, "#{entry[:out]}.mp3")
    prev = %w[TRACK BARS BPM PROGRESSION SWING SONITEX SONITEX_PRESET ANALOG_CHAIN].each_with_object({}) { |k, h| h[k] = ENV[k] }
    ENV["TRACK"]   = entry[:preset].to_s
    ENV["BARS"]    = entry[:bars].to_s
    ENV["SONITEX"] = "heavy"
    ENV["SONITEX_PRESET"] = "heavy"
    ENV["ANALOG_CHAIN"] = ANALOG_CHAIN_ROTATE[i % ANALOG_CHAIN_ROTATE.length].to_s
    render_dilla(dest, entry[:bars])
  ensure
    prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
  puts "tape batch: #{TAPE_RENDER_CATALOG.length} sessions → #{output_dir}"
end

# Full-length MPC hip-hop: Slum Village Vol. 1/2 presets via TRACK= env.
def render_hiphop(destination = File.join(OUTPUT_DIR, "hiphop.mp3"))
  prev = %w[BPM BARS TRACK PROGRESSION SWING].each_with_object({}) { |k, h| h[k] = ENV[k] }
  ENV["TRACK"] ||= "syncopated_slash_ninth"
  ENV["BARS"] ||= "63"
  render_dilla(destination, bars)
ensure
  prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
end
