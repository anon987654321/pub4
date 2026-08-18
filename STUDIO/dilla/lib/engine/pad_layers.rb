# frozen_string_literal: true
#
# Extra pad layers: chopped singers, stretched melody, tunnel, choir, granular cloud.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- Singers Unlimited chop pads -------------------------------------------
# The pad bed built from CHOPS of a real Singers Unlimited vocal stem instead
# of synth pads (classic Dilla move: chop the vocal-harmony record). Per pad
# event, a phrase chop is repitched via asetrate (true tape/chipmunk repitch,
# artifacts intended) to the chord root plus up to two upper chord tones, so
# the chop harmonizes itself to the progression regardless of the source key.
# Default OFF (SINGERS_CHOP_PADS=1 enables). When this succeeds it replaces the
# synth pad stack *entirely* -- so with it on by default the real pads (the
# fluidsynth stack, the patch catalog, PAD_VOICE, every voice-leading decision)
# never reached the mix at all; the chords you heard were repitched vocal chops.
# It is an effect, not the pad engine, so it has to be opted into. Enable with
# SINGERS_CHOP_PADS=1, which needs a stem:
#   ruby dilla.rb rap-vocal ingest singers_unlimited <youtube-url-or-path>
def singers_chop_pads_enabled?
  ENV.fetch("SINGERS_CHOP_PADS", "0") != "0"
end

def singers_chop_source
  entry = Array(rap_vocal_load_catalog["vocals"]).find { |v| v["slug"] == "singers_unlimited" }
  path = entry && entry["vocal_path"].to_s
  path = File.join(RAP_VOCAL_DIR, "singers_unlimited", "vocals.wav") if path.nil? || path.empty?
  return unless File.file?(path)

  { path:, phrases: Array(entry&.dig("phrases")).map { |p| p["start"].to_f }.select(&:positive?) }
end

def render_singers_chop_pads(path, pad_events, duration)
  src = singers_chop_source
  return unless src

  src_dur = audio_duration_sec(src[:path])
  return if src_dur < 8.0

  rng = Random.new((@render_seed || 4242) + 555)
  starts = src[:phrases].select { |s| s < src_dur - 6.0 }
  starts = Array.new(12) { rng.rand * (src_dur - 6.0) } if starts.empty?
  first_root = nil
  chains = []
  labels = []
  pad_events.each_with_index do |(t, v, chord, sustain), i|
    next unless chord.is_a?(Hash) && chord[:hz].is_a?(Array) && chord[:hz].any?

    hz = chord[:hz].map(&:to_f).select(&:positive?).sort
    next if hz.empty?

    root = hz.first
    first_root ||= root
    # Root motion relative to the first chord, octave-folded so the repitch
    # never leaves believable tape range.
    base = root / first_root
    base /= 2.0 while base > 1.6
    base *= 2.0 while base < 0.7
    chop_at = starts[(i * 7 + rng.rand(3)) % starts.length]
    # Root voice + up to two upper chord tones (ratio to root, folded ≤ 2x).
    voices = [1.0] + hz.drop(1).take(3).map do |h|
      r = h / root
      r /= 2.0 while r > 2.05
      r
    end
    voices.take(3).each_with_index do |ratio, vi|
      r = (base * ratio).clamp(0.5, 2.1)
      need = sustain.to_f * r + 0.4
      s0 = chop_at.clamp(0.0, [src_dur - need - 0.1, 0.0].max)
      fade_out_at = [sustain.to_f - 0.3, 0.05].max
      gain = (v.to_f * (vi.zero? ? 0.95 : 0.5)).round(3)
      delay_ms = [(t * 1000.0).round, 0].max
      lbl = "sc#{i}v#{vi}"
      chains << "[0:a]atrim=start=#{s0.round(3)}:end=#{(s0 + need).round(3)},asetpts=PTS-STARTPTS," \
                "aformat=channel_layouts=stereo,asetrate=#{SAMPLE_RATE}*#{r.round(4)},aresample=#{SAMPLE_RATE}," \
                "afade=t=in:st=0:d=0.08,afade=t=out:st=#{fade_out_at.round(3)}:d=0.3," \
                "atrim=0:#{sustain.round(3)},volume=#{gain},adelay=#{delay_ms}|#{delay_ms}[#{lbl}]"
      labels << "[#{lbl}]"
    end
  end
  return if labels.empty?

  filt = "#{chains.join(';')};#{labels.join}" \
         "amix=inputs=#{labels.length}:duration=longest:normalize=0," \
         "atrim=0:#{duration},highpass=f=#{pad_highpass_hz},alimiter=limit=0.95:level_out=0.96[pads]"
  prev_soft = ENV["DILLA_SOFT_SH"]
  ENV["DILLA_SOFT_SH"] = "1"
  begin
    sh! "ffmpeg", "-y", "-i", src[:path], "-filter_complex", filt,
        "-map", "[pads]", "-c:a", "pcm_s16le", path
  rescue StandardError => e
    warn "singers chop pads failed (#{e.message}) — falling back to synth pads"
    FileUtils.rm_f(path)
    return
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
  end
  return unless File.file?(path)

  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (PAD_TARGET_RMS_DB - measured_rms).clamp(-24.0, 24.0)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "equalizer=f=320:t=o:w=1:g=1.2,volume=#{boost_db.round(2)}dB," \
      "alimiter=limit=0.95:level_out=0.96",
      "-c:a", "pcm_s16le", "#{path}.sc.wav"
  FileUtils.mv("#{path}.sc.wav", path)
  dmesg("singers unlimited chop bed (#{labels.length} voices)", unit: "harm0", parent: "dilla0")
  path
end

# The Singers Unlimited harmony as the track's melodic voice, resynthesized
# rather than played back.
#
# render_singers_chop_pads above is varispeed tape: atrim a phrase, asetrate it
# to the chord, done. That keeps the vocal sounding like a vocal, which is why
# it reads as a bed. This path spectrally resynthesizes instead — magnitudes
# kept, phase discarded — so the ensemble stops being four people singing and
# becomes a sustained harmonic instrument that still carries their voicing.
# That is the whole point: the melody is not played BY a synth, the choir IS
# the synth.
#
# Phase randomization is the Paulstretch core (huge windows, random phase,
# heavy overlap-add). ffmpeg has no paulstretch filter and no rubberband here,
# so afftfilt supplies the phase discard and atempo=0.5 supplies the exact 2x
# stretch that holds pitch. Measured on the real sample: band energy at 200/400/
# 900/2500 Hz tracks the dry signal within 0.3 dB of a uniform 6 dB drop, so the
# voicing survives intact and only the level moves — hence the fixed +6 dB.
SU_MELODY_VARIANTS = 4
SU_MELODY_WIN = 8192
# How much untouched signal sits under the resynthesis. Enough to return the
# attacks; past roughly 0.5 the source stops sounding like an instrument and
# starts sounding like a vocal sample again, which is the thing this is not.
SU_MELODY_DRY_BLEND = (ENV["SU_MELODY_DRY"] || 0.34).to_f.clamp(0.0, 1.0)

def su_melody_enabled?
  ENV.fetch("SU_MELODY", "0") != "0"
end

def no_lead?
  ENV.fetch("NO_LEAD", "0") != "0"
end

def grand_pads? = ENV.fetch("GRAND", "0") != "0"

# Grandeur by orchestration rather than by EQ.
#
# With no lead the pads are the whole record, and a four-voice stack in one
# octave is a small sound however it is filtered. Weight and scale in an organ
# registration or a string section come from the same notes doubled at the
# octave -- a 16-foot stop under the 8-foot, basses under the celli. Boosting
# low end instead only makes the same narrow voicing heavier, which is muddier,
# not bigger.
#
# The octave below carries the root and fifth only. Doubling a ninth or a
# thirteenth down there turns an extension into a low interval that beats
# against the root, which is why the low copy is filtered rather than complete.
# The octave above takes the upper voices, where it reads as air.
GRAND_LOW_GAIN = 0.55
GRAND_HIGH_GAIN = 0.38

def grandeur_pad_events(pad_events)
  pad_events.flat_map do |event|
    t, v, chord, sustain = event
    next [event] unless chord.is_a?(Hash) && chord[:hz].is_a?(Array)

    hz = chord[:hz].map(&:to_f).select(&:positive?).sort
    next [event] if hz.length < 2

    root = hz.first
    # Root and fifth only: within 60 cents of a 3:2, octave-folded.
    low = hz.select do |h|
      ratio = h / root
      ratio /= 2.0 while ratio > 2.0
      (ratio - 1.0).abs < 0.03 || (ratio - 1.5).abs < 0.05
    end
    out = [event]
    if low.any?
      out << [t, v * GRAND_LOW_GAIN, chord.merge(hz: low.map { |h| h / 2.0 },
                                                 name: "#{chord[:name]}_8vb"), sustain]
    end
    upper = hz.drop(1)
    if upper.any?
      out << [t, v * GRAND_HIGH_GAIN, chord.merge(hz: upper.map { |h| h * 2.0 },
                                                  name: "#{chord[:name]}_8va"), sustain]
    end
    out
  end
end

# One afftfilt pass per variant instead of one per note. Per-note stretching
# measured 9.4s for 24 voices, which extrapolates to ~61s on a three-minute
# track and scales with length; this is a fixed four passes regardless.
def su_melody_stretched_sources(src, src_dur, tmp_dir, rng)
  SU_MELODY_VARIANTS.times.filter_map do |i|
    grab = 9.0
    at = 6.0 + rng.rand * [src_dur - grab - 8.0, 1.0].max
    out = File.join(tmp_dir, "su_stretch#{i}.wav")
    begin
      # Part resynthesised, part not.
      #
      # Discarding all phase gives a perfectly smooth drone and no instrument:
      # every transient in the source is gone, so nothing has an attack and the
      # result is a wash that sits behind the track rather than a voice that
      # plays it. That is the "synth patch" complaint. Blending the untouched
      # signal back under the phase-randomised one returns the consonant edges
      # and the breath while keeping the sustain the stretch created -- the
      # spectral part supplies the tone, the dry part supplies the articulation.
      sh! "ffmpeg", "-y", "-v", "error", "-ss", at.round(3).to_s, "-t", grab.to_s, "-i", src,
          "-filter_complex",
          "[0:a]aformat=channel_layouts=stereo,atempo=0.5,asplit=2[sd][sw];" \
          "[sw]afftfilt=real='hypot(re,im)*cos(random(#{i + 1})*2*PI)':" \
          "imag='hypot(re,im)*sin(random(#{i + 1})*2*PI)':" \
          "win_size=#{SU_MELODY_WIN}:overlap=0.94,volume=6dB[swet];" \
          "[sd]highpass=f=180,volume=-3dB[sdry];" \
          "[swet][sdry]amix=inputs=2:weights=1 #{SU_MELODY_DRY_BLEND}:duration=first:normalize=0[out]",
          "-map", "[out]", "-c:a", "pcm_s16le", out
    rescue StandardError => e
      warn "su melody variant #{i} skipped: #{e.message}"
      next
    end
    File.file?(out) && File.size(out) > 4096 ? out : nil
  end
end

# Resonant low-mid, absorbed highs, irregular short taps. A tunnel is a
# resonance and an absorption, not a reverb preset — the short taps are the
# flutter between close walls, the long pair is the far end. Applied to the
# summed voices so they share one space rather than each sitting in its own.
# Operator note 2026-08-13: the tunnel read as too loud in the techno set. Two
# gains came down and nothing else moved — the tap structure above is the
# character and cutting it would have made a different effect rather than a
# quieter one.
#
#   520 Hz resonance  +6 dB -> +2 dB   the low-mid honk, the loudest single thing
#                                      in the chain and what "too loud" hears
#   stereotools slev  1.35 -> 1.15     sides came back toward centre; a widened
#                                      tunnel reads louder than it measures
SU_TUNNEL_CHAIN = "highpass=f=90," \
                  "equalizer=f=520:t=q:w=1.4:g=2," \
                  "equalizer=f=1900:t=q:w=2.0:g=-4," \
                  "lowpass=f=3400," \
                  "aecho=0.82:0.85:37|59|83|127:0.5|0.38|0.28|0.18," \
                  "aecho=0.9:0.8:311|487:0.22|0.14," \
                  "stereotools=mlev=0.9:slev=1.15"

# The refined tunnel: a convolved impulse response instead of six discrete taps.
#
# The chain above is four short echoes at 37/59/83/127 ms and a far pair. Taps
# that short are a comb filter, not a room -- each one puts a fixed notch in the
# spectrum, and four of them on a sustained choir is a metallic ring sitting on
# every held note. That is what reads as unrefined, and no amount of tuning the
# gains fixes it, because the artefact is the discreteness itself.
#
# A real tunnel tail is dense: thousands of reflections, too close together to
# hear individually, getting darker as they decay because air and concrete
# absorb treble faster than bass. That is an impulse response, so this generates
# one -- exponentially decaying noise, low-passed progressively over its length,
# with the early part shaped to keep the close-wall character the taps were
# there for -- and convolves it with afir.
SU_TUNNEL_IR_SEC = 1.9
SU_TUNNEL_IR_RATE = 44_100

def su_tunnel_ir_path(dir)
  path = File.join(dir, "su_tunnel_ir.wav")
  return path if File.file?(path) && File.size(path) > 4096

  frames = (SU_TUNNEL_IR_SEC * SU_TUNNEL_IR_RATE).to_i
  rng = Random.new(90_210)
  # Two decorrelated channels, or the tail collapses to the middle and the
  # tunnel has no width at all.
  samples = Array.new(2) { Array.new(frames, 0.0) }
  2.times do |ch|
    lp = 0.0
    frames.times do |i|
      t = i.to_f / SU_TUNNEL_IR_RATE
      # Exponential decay, plus a short pre-delay so the direct sound is not
      # smeared into its own reflections.
      env = t < 0.006 ? 0.0 : Math.exp(-4.2 * t)
      # Progressive damping: the coefficient falls as the tail ages, so late
      # reflections are darker than early ones the way absorption makes them.
      a = 0.55 - (0.35 * (t / SU_TUNNEL_IR_SEC))
      lp += a * ((rng.rand * 2.0 - 1.0) - lp)
      samples[ch][i] = lp * env
    end
    peak = samples[ch].max_by(&:abs).abs
    samples[ch].map! { |v| v / peak * 0.7 } if peak.positive?
  end

  File.open(path, "wb") do |f|
    data_bytes = frames * 2 * 2
    f.write("RIFF"); f.write([36 + data_bytes].pack("V")); f.write("WAVEfmt ")
    f.write([16, 1, 2, SU_TUNNEL_IR_RATE, SU_TUNNEL_IR_RATE * 4, 4, 16].pack("VvvVVvv"))
    f.write("data"); f.write([data_bytes].pack("V"))
    frames.times do |i|
      f.write([(samples[0][i] * 32_767).round.clamp(-32_768, 32_767),
               (samples[1][i] * 32_767).round.clamp(-32_768, 32_767)].pack("s<s<"))
    end
  end
  path
end

def su_tunnel_refined? = ENV.fetch("SU_TUNNEL_REFINED", "1") != "0"

SU_MELODY_TARGET_RMS_DB = -17.0

def render_su_tunnel_melody(path, pad_events, duration, cfg: nil, n_bars: nil)
  src = singers_chop_source
  return unless src

  src_dur = audio_duration_sec(src[:path])
  return if src_dur < 20.0

  rng = Random.new((@render_seed || 4242) + 909)
  tmp_dir = File.dirname(path)
  sources = su_melody_stretched_sources(src[:path], src_dur, tmp_dir, rng)
  return if sources.empty?

  # The tune, from the engine's own line writer rather than this renderer's
  # arpeggiator. Rendered by the choir instead of a soundfont, so the melody is
  # written by the part of the engine that knows how to write one and voiced by
  # the part that sounds good.
  tune = if cfg
           begin
             lead_events_melodic(pad_events, cfg, duration: duration, n_bars: n_bars)
           rescue StandardError => e
             warn "su melody line fell back to held chords: #{e.message}"
             []
           end
         else
           []
         end

  stretched_dur = sources.map { |s| audio_duration_sec(s) }
  first_root = nil
  chains = []
  labels = []
  idx = 0

  pad_events.each_with_index do |(t, v, chord, sustain), ci|
    next unless chord.is_a?(Hash) && chord[:hz].is_a?(Array) && chord[:hz].any?

    hz = chord[:hz].map(&:to_f).select(&:positive?).sort
    next if hz.empty?

    root = hz.first
    first_root ||= root
    sus = sustain.to_f
    next if sus <= 0.05

    # The held pair only. The top line used to be built here by stepping through
    # top_tones[(ci + s) % length] -- a cycle through the chord's own notes,
    # indexed by which chord it was. That is an arpeggiator, not a melody: no
    # contour, no phrase, no motif, the same shape over every chord, and it
    # never rests. It is why the lead was unlistenable.
    #
    # The tune now comes from lead_events_melodic, which the engine already had:
    # a motif stated then inverted and reversed across phrases, notes chosen by
    # lead_note_score against parallel fifths and oversized leaps, whole phrases
    # left silent by lead_phrase_rests?, contrary motion to the pad top. All of
    # that existed and this renderer walked past it to roll its own.
    held = hz.take(2)
    voices = held.map { |h| [h, 0.0, sus, h == root ? 0.9 : 0.5] }

    voices.each do |(target, offset, length, gain)|
      r = target / first_root
      r /= 2.0 while r > 1.9
      r *= 2.0 while r < 0.85
      si = (ci + idx) % sources.length
      need = length * r + 0.4
      avail = [stretched_dur[si] - need - 0.1, 0.0].max
      next if avail <= 0.0

      s0 = (rng.rand * avail).round(3)
      delay_ms = [((t + offset) * 1000.0).round, 0]
      delay_ms = delay_ms.max
      fade_in = [length * 0.3, 0.9].min
      fade_at = [length - fade_in, 0.05].max
      lbl = "sm#{idx}"
      idx += 1

      chains << "[#{si}:a]atrim=start=#{s0}:end=#{(s0 + need).round(3)},asetpts=PTS-STARTPTS," \
                "aformat=channel_layouts=stereo," \
                "asetrate=#{SAMPLE_RATE}*#{r.round(5)},aresample=#{SAMPLE_RATE}," \
                "atrim=0:#{length.round(3)}," \
                "afade=t=in:st=0:d=#{fade_in.round(3)}," \
                "afade=t=out:st=#{fade_at.round(3)}:d=#{fade_in.round(3)}," \
                "volume=#{(v.to_f * gain).round(3)}," \
                "adelay=#{delay_ms}|#{delay_ms}[#{lbl}]"
      labels << "[#{lbl}]"
    end
  end

  # The melody itself, one choir voice per written note, louder than the held
  # pair so it reads as the line and they read as the ground under it.
  tune.each_with_index do |(t, v, note, sustain), ni|
    nhz = note.is_a?(Hash) ? Array(note[:hz]).map(&:to_f).select(&:positive?) : []
    target = nhz.first
    next unless target

    length = sustain.to_f
    next if length <= 0.05

    first_root ||= target
    r = target / first_root
    r /= 2.0 while r > 1.9
    r *= 2.0 while r < 0.85
    si = (ni + 1) % sources.length
    need = length * r + 0.4
    avail = [stretched_dur[si] - need - 0.1, 0.0].max
    next if avail <= 0.0

    s0 = (rng.rand * avail).round(3)
    delay_ms = [(t.to_f * 1000.0).round, 0].max
    # A shorter attack than the bed. The bed swells over 0.3 of its length,
    # which is right for something held and wrong for a sung note -- it is what
    # made every entry vague instead of articulate.
    fade_in = [length * 0.12, 0.22].min
    fade_out = (length * 0.3).round(3)
    fade_at = [length - fade_out, 0.05].max
    lbl = "sl#{ni}"

    chains << "[#{si}:a]atrim=start=#{s0}:end=#{(s0 + need).round(3)},asetpts=PTS-STARTPTS," \
              "aformat=channel_layouts=stereo," \
              "asetrate=#{SAMPLE_RATE}*#{r.round(5)},aresample=#{SAMPLE_RATE}," \
              "atrim=0:#{length.round(3)}," \
              "afade=t=in:st=0:d=#{fade_in.round(3)}," \
              "afade=t=out:st=#{fade_at.round(3)}:d=#{fade_out}," \
              "volume=#{(v.to_f * 1.15).round(3)}," \
              "adelay=#{delay_ms}|#{delay_ms}[#{lbl}]"
    labels << "[#{lbl}]"
  end
  dmesg("su melody line: #{tune.length} written notes over #{pad_events.length} chords",
        unit: "harm0", parent: "dilla0")
  return if labels.empty?

  ir = su_tunnel_refined? ? su_tunnel_ir_path(tmp_dir) : nil
  if ir
    # Convolution replaces the tap chain; the tone shaping stays, since the IR
    # supplies the room and not the resonance.
    space = "highpass=f=90,equalizer=f=520:t=q:w=1.4:g=5," \
            "equalizer=f=1900:t=q:w=2.0:g=-3.5,lowpass=f=3600"
    wet = "[mixed]#{space}[dry_t];" \
          "[dry_t]asplit=2[t_dry][t_wet];" \
          "[t_wet][#{sources.length}:a]afir=dry=0:wet=1:gtype=peak:maxir=#{SU_TUNNEL_IR_SEC}[t_verb];" \
          "[t_dry][t_verb]amix=inputs=2:weights=1 0.85:duration=first:normalize=0," \
          "stereotools=mlev=0.9:slev=1.3"
    filt = "#{chains.join(';')};#{labels.join}" \
           "amix=inputs=#{labels.length}:duration=longest:normalize=0[mixed];" \
           "#{wet},atrim=0:#{duration},alimiter=limit=0.95:level_out=0.94[su]"
  else
    filt = "#{chains.join(';')};#{labels.join}" \
           "amix=inputs=#{labels.length}:duration=longest:normalize=0," \
           "#{SU_TUNNEL_CHAIN},atrim=0:#{duration}," \
           "alimiter=limit=0.95:level_out=0.94[su]"
  end
  inputs = sources.flat_map { |s| ["-i", s] }
  inputs += ["-i", ir] if ir
  prev_soft = ENV["DILLA_SOFT_SH"]
  ENV["DILLA_SOFT_SH"] = "1"
  begin
    sh! "ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", filt,
        "-map", "[su]", "-c:a", "pcm_s16le", path
  rescue StandardError => e
    warn "su tunnel melody failed (#{e.message})"
    FileUtils.rm_f(path)
    return
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
    sources.each { |s| FileUtils.rm_f(s) }
  end
  return unless File.file?(path)

  normalize_wav_to_rms!(path, SU_MELODY_TARGET_RMS_DB)
  dmesg("su tunnel melody (#{labels.length} voices, #{sources.length} stretched sources)",
        unit: "harm0", parent: "dilla0")
  path
end

# Soft choir pad on chord tones (Singers Unlimited–like ooh/aah). Default on
# via CHOIR_VOX=1; set CHOIR_VOX=0 to disable. Gain via CHOIR_VOX_GAIN (0–1).
def choir_vox_enabled?
  # Default off, matching DILLA_STYLE_DEFAULTS. This gate is the one that
  # decides, and it defaulted on — so any path that does not apply the style
  # table still got a choir.
  ENV.fetch("CHOIR_VOX", "0") != "0" && fluidsynth_pad_available?
end

# Thin full pad voicings to 2–3 mid/upper chord tones so choir reads as
# airy harmony, not a second dense pad stack.
def choir_chord_tone_events(pad_events)
  pad_events.filter_map do |(t, v, chord, sustain)|
    next unless chord.is_a?(Hash) && chord[:hz].is_a?(Array) && chord[:hz].any?

    sorted = chord[:hz].map(&:to_f).select(&:positive?).sort
    next if sorted.empty?

    # Prefer 3rd + 5th + 7th/9th when available; drop the bass note if dense.
    tones =
      if sorted.length >= 4
        [sorted[1], sorted[2], sorted[-1]]
      elsif sorted.length == 3
        sorted
      else
        sorted
      end
    # Lift into choir register (~C4–C5) without changing pitch class.
    lifted = tones.map do |hz|
      h = hz
      h *= 2 while h < 220.0
      h /= 2 while h > 880.0
      h
    end.uniq
    next if lifted.empty?

    soft_v = (v.to_f * 0.72).clamp(0.15, 0.85)
    [t, soft_v, chord.merge(hz: lifted, name: "#{chord[:name]}·choir"), sustain]
  end
end

def render_choir_vox_layer(path, pad_events, duration)
  events = choir_chord_tone_events(pad_events)
  return if events.empty?

  seed = (@render_seed || 0).to_i
  patch_id = (seed + events.length).even? ? :choir_aahs : :voice_oohs
  patch = synth_patch_by_id(patch_id) || synth_patch_by_id(:choir_aahs)
  return unless patch

  voice = patch_voice_for(patch) || { sf2: pad_soundfont_path, bank: 0, program: 52, patch: }
  voice = voice.merge(patch:) if voice[:patch].nil?
  # Soft: never abort the whole track for choir failures.
  prev_soft = ENV["DILLA_SOFT_SH"]
  ENV["DILLA_SOFT_SH"] = "1"
  begin
    render_one_pad_layer!(path, events, duration, voice, :warm)
  rescue StandardError => e
    warn "choir_vox layer skipped: #{e.message}"
    FileUtils.rm_f(path)
    return
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
  end
  return unless File.file?(path)

  soft = "#{path}.soft.wav"
  gain = (ENV["CHOIR_VOX_GAIN"] || "0.28").to_f.clamp(0.05, 0.65)
  begin
    ENV["DILLA_SOFT_SH"] = "1"
    sh! "ffmpeg", "-y", "-i", path, "-af",
        "afade=t=in:st=0:d=0.9,highpass=f=200,lowpass=f=4200," \
        "aecho=0.55:0.6:120|220:0.28|0.14,volume=#{gain.round(3)}," \
        "alimiter=limit=0.72:level_out=0.78",
        "-c:a", "pcm_s16le", soft
    FileUtils.mv(soft, path) if File.file?(soft)
  rescue StandardError => e
    warn "choir_vox soft pass skipped: #{e.message}"
    FileUtils.rm_f(soft)
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
  end
  File.file?(path) ? path : nil
end

def mix_choir_into_pads!(pads_path, choir_path, duration)
  return unless pads_path && choir_path && File.file?(pads_path) && File.file?(choir_path)

  out = "#{pads_path}.choir_mix.wav"
  prev_soft = ENV["DILLA_SOFT_SH"]
  ENV["DILLA_SOFT_SH"] = "1"
  begin
    sh! "ffmpeg", "-y", "-i", pads_path, "-i", choir_path,
        "-filter_complex",
        "[0:a]apad=whole_dur=#{duration}[p];[1:a]apad=whole_dur=#{duration}[c];" \
        "[p][c]amix=inputs=2:weights=1.0 0.55:duration=first:normalize=0," \
        "alimiter=limit=0.96:level_out=0.97[out]",
        "-map", "[out]", "-t", duration.to_s, "-c:a", "pcm_s16le", out
    FileUtils.mv(out, pads_path) if File.file?(out)
  rescue StandardError => e
    warn "choir_vox mix skipped: #{e.message}"
    FileUtils.rm_f(out)
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
    FileUtils.rm_f(choir_path)
  end
end

# --- Granular pad texture (Clouds/Beads-style micro-grain resynthesis) ------
# The rendered pad bed is re-read as mono and rebuilt from 60–200 ms
# hann-windowed grains — position spray trailing the playhead, occasional
# +1-octave shimmer and sub-octave haze grains, some reversed — then floated
# back under the bed. Grain scheduling and synthesis are pure Ruby (same DSP
# idiom as karplus_strong_pluck/write_stereo_chunks); ffmpeg only decodes the
# source and applies the final tone/space pass. Default on; PAD_GRANULAR=0
# disables. Knobs: PAD_GRAIN_MIX, PAD_GRAIN_SIZE_MS, PAD_GRAIN_DENSITY
# (grains/sec), PAD_GRAIN_SPRAY_MS, PAD_GRAIN_SHIMMER, PAD_GRAIN_REVERSE.
def pad_granular_enabled?
  ENV.fetch("PAD_GRANULAR", "1") != "0"
end

def pad_granular_settings
  {
    mix: (ENV["PAD_GRAIN_MIX"] || "0.5").to_f.clamp(0.05, 1.0),
    size_ms: (ENV["PAD_GRAIN_SIZE_MS"] || "120").to_f.clamp(30.0, 400.0),
    density: (ENV["PAD_GRAIN_DENSITY"] || "12").to_f.clamp(2.0, 40.0),
    spray_ms: (ENV["PAD_GRAIN_SPRAY_MS"] || "260").to_f.clamp(0.0, 1200.0),
    shimmer: (ENV["PAD_GRAIN_SHIMMER"] || "0.18").to_f.clamp(0.0, 1.0),
    reverse: (ENV["PAD_GRAIN_REVERSE"] || "0.25").to_f.clamp(0.0, 1.0),
  }
end

# Chord segments as [start_frame, end_frame) so grains can be confined to
# the chord sounding at their own onset. Without this the spray let grains
# of the PREVIOUS chord ring over the next one — on chromatic progressions
# (root moves by semitone) that smear is a straight-up dissonant mush.
def pad_grain_segments(pad_events, duration, source_frames)
  times = Array(pad_events).filter_map { |(t, _v, chord, _s)| t.to_f if chord }.sort
  return [[0, source_frames]] if times.length < 2

  bounds = times.map { |t| (t * SAMPLE_RATE).to_i.clamp(0, source_frames) }
  bounds << (duration * SAMPLE_RATE).to_i.clamp(0, source_frames)
  bounds.each_cons(2).map { |(a, b)| [a, b] }.reject { |(a, b)| b - a < 1200 }
end

def pad_grain_events(duration, source_frames, rng, grain_cfg, segments: nil)
  segments = [[0, source_frames]] if segments.nil? || segments.empty?
  size_frames = (grain_cfg[:size_ms] * SAMPLE_RATE / 1000.0).to_i
  spray_frames = (grain_cfg[:spray_ms] * SAMPLE_RATE / 1000.0).to_i
  step = 1.0 / grain_cfg[:density]
  grains = []
  t = 0.0
  while t < duration
    start_frame = [(t * SAMPLE_RATE).to_i + rng.rand(-1200..1200), 0].max
    seg = segments.reverse_each.find { |(a, _b)| a <= start_frame } || segments.first
    pitch = if rng.rand < grain_cfg[:shimmer] then 2.0
            elsif rng.rand < 0.10 then 0.5
            else 1.0
            end
    # Grain must fit inside its own chord's segment — shrink it on short
    # segments, and skip when even a minimum grain can't fit.
    seg_len = seg[1] - seg[0]
    len = (size_frames * rng.rand(0.6..1.4)).to_i.clamp(600, source_frames)
    len = [len, ((seg_len - 2) / pitch).to_i].min
    if len < 600
      t += step
      next
    end
    src_lo = seg[0]
    src_hi = [seg[1] - (len * pitch).ceil - 2, src_lo].max
    # Spray trails the playhead (granular tail, not pre-echo) but never
    # crosses back past the chord boundary.
    src = (start_frame - rng.rand(0..spray_frames)).clamp(src_lo, src_hi)
    grains << { start: start_frame, len:, src:, pitch:,
                rev: rng.rand < grain_cfg[:reverse], pan: rng.rand(-0.7..0.7),
                # Cloud swells toward the end of the piece — quiet entrance,
                # denser-feeling texture as the track develops.
                amp: rng.rand(0.45..0.9) * (0.65 + 0.35 * (t / duration)) }
    t += step * rng.rand(0.55..1.45)
  end
  grains
end

def render_pad_granular_layer(path, pads_path, duration, pad_events = nil)
  raw, = Open3.capture2("ffmpeg", "-v", "error", "-i", pads_path,
                        "-f", "f32le", "-ac", "1", "-ar", SAMPLE_RATE.to_s, "pipe:1")
  return if raw.nil? || raw.length < 4 * SAMPLE_RATE # under a second of source

  source = raw.unpack("e*")
  grain_cfg = pad_granular_settings
  rng = Random.new((@render_seed || 4242) + 977)
  segments = pad_events ? pad_grain_segments(pad_events, duration, source.length) : nil
  grains = pad_grain_events(duration, source.length, rng, grain_cfg, segments:)
  return if grains.empty?

  write_stereo_chunks(path, duration) do |chunk_start, chunk_frames, left, right|
    grains.each do |g|
      window = overlap_window(g[:start], g[:len], chunk_start, chunk_frames)
      next unless window

      dst0, grain0, count = window
      count.times do |i|
        j = grain0 + i
        pos = g[:rev] ? (g[:len] - 1 - j) : j
        sp = g[:src] + pos * g[:pitch]
        base = sp.to_i
        frac = sp - base
        s = (source[base] || 0.0) * (1.0 - frac) + (source[base + 1] || 0.0) * frac
        s *= 0.5 * (1.0 - Math.cos(2.0 * Math::PI * j / g[:len])) * g[:amp]
        left[dst0 + i] += s * (0.5 - g[:pan] * 0.5)
        right[dst0 + i] += s * (0.5 + g[:pan] * 0.5)
      end
    end
  end
  # Tone/space polish then RMS-target the cloud ~9 dB under the bed it was
  # granulated from — raw grain sums land 20+ dB down (hann window + pan
  # split + duty cycle) and the polish chain loses more (aecho in_gain), so
  # the boost is measured AFTER polish, pad-master style. Never abort the
  # whole track for a texture layer.
  soft = "#{path}.soft.wav"
  prev_soft = ENV["DILLA_SOFT_SH"]
  ENV["DILLA_SOFT_SH"] = "1"
  begin
    sh! "ffmpeg", "-y", "-i", path, "-af",
        "afade=t=in:st=0:d=1.2,highpass=f=170,lowpass=f=4600," \
        "aecho=0.5:0.5:70|130:0.2|0.1",
        "-c:a", "pcm_s16le", soft
    FileUtils.mv(soft, path) if File.file?(soft)
    pad_rms = band_rms(pads_path, highpass: 20, lowpass: 20_000)
    grain_rms = band_rms(path, highpass: 20, lowpass: 20_000)
    boost_db = (pad_rms - 9.0 - grain_rms).clamp(0.0, 30.0)
    sh! "ffmpeg", "-y", "-i", path, "-af",
        "volume=#{boost_db.round(2)}dB,alimiter=limit=0.95:level_out=0.96",
        "-c:a", "pcm_s16le", soft
    FileUtils.mv(soft, path) if File.file?(soft)
  rescue StandardError => e
    warn "pad granular polish skipped: #{e.message}"
    FileUtils.rm_f(soft)
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
  end
  File.file?(path) ? path : nil
end

def mix_granular_into_pads!(pads_path, grain_path, duration)
  return unless pads_path && grain_path && File.file?(pads_path) && File.file?(grain_path)

  out = "#{pads_path}.grain_mix.wav"
  weight = pad_granular_settings[:mix]
  # Duck the cloud when a vocal rides this track — the grain texture is
  # exactly the "mylder" a quiet vocal stem drowns in.
  rap_slug = ENV["RAP_VOCAL"].to_s
  weight *= 0.6 unless rap_slug.empty? || rap_slug == "0"
  prev_soft = ENV["DILLA_SOFT_SH"]
  ENV["DILLA_SOFT_SH"] = "1"
  begin
    sh! "ffmpeg", "-y", "-i", pads_path, "-i", grain_path,
        "-filter_complex",
        "[0:a]apad=whole_dur=#{duration}[p];[1:a]apad=whole_dur=#{duration}[g];" \
        "[p][g]amix=inputs=2:weights=1.0 #{weight.round(3)}:duration=first:normalize=0," \
        "alimiter=limit=0.96:level_out=0.97[out]",
        "-map", "[out]", "-t", duration.to_s, "-c:a", "pcm_s16le", out
    FileUtils.mv(out, pads_path) if File.file?(out)
  rescue StandardError => e
    warn "pad granular mix skipped: #{e.message}"
    FileUtils.rm_f(out)
  ensure
    prev_soft ? ENV["DILLA_SOFT_SH"] = prev_soft : ENV.delete("DILLA_SOFT_SH")
    FileUtils.rm_f(grain_path)
  end
end
