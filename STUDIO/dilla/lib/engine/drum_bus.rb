# frozen_string_literal: true
#
# Drum bus routing: FlyLo dual bus, ducking, field layer, drop bars.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# "All his drums are dirty as fuck, sans the kick" -- and the cymbals in
# particular are swished through phaser and flanger until they are soupy rather
# than crisp.
#
# The dual-bus split already separates exactly the right things: the sub bus is
# the kick, the top bus is hats, snare and cymbals. So the dirt goes on the top
# branch and the kick stays untouched, which is the distinction being described
# rather than an approximation of it. Applying this to the whole kit would
# smear the one element that has to stay solid.
#
# Order matters: modulation BEFORE the EQ, so the phaser's own notches get
# shaped by the top-end lift rather than fighting it, and light saturation last
# so it thickens what the modulation produced.
FLYLO_TOP_DIRT = (ENV["FLYLO_TOP_DIRT"] || 0).to_f.clamp(0.0, 1.0)

def flylo_top_dirt
  return "" if FLYLO_TOP_DIRT <= 0.0

  d = FLYLO_TOP_DIRT
  "aphaser=in_gain=0.6:out_gain=0.8:delay=#{(2.5 + (2.0 * d)).round(2)}:" \
    "decay=#{(0.3 * d).round(3)}:speed=#{(0.35 + (0.5 * d)).round(3)}," \
    "flanger=delay=#{(3.0 + (4.0 * d)).round(2)}:depth=#{(2.0 * d).round(2)}:" \
    "regen=#{(12.0 * d).round(1)}:speed=#{(0.28 + (0.4 * d)).round(3)}," \
    "acrusher=bits=#{(16 - (5 * d)).round}:mode=log:aa=1," \
    "asoftclip=type=tanh:threshold=#{(1.0 - (0.35 * d)).round(3)}:oversample=4,"
end

# Duck the hats and cymbals out of the kick's way.
#
# Named twice in the same discussion for a reason: when a hat lands on the same
# 16th as the kick, both fight for the same moment and the kick loses definition
# even though nothing overlaps in frequency. Ducking the top bus for a few tens
# of milliseconds lets the kick through cleanly and is inaudible as an effect --
# the hat is still there, it arrives a fraction behind.
#
# The dual-bus split makes this exact rather than approximate: the sub bus IS
# the kick, so it can key the compressor directly instead of using the whole kit
# as a trigger and ducking on every snare too.
FLYLO_HAT_DUCK = (ENV["FLYLO_HAT_DUCK"] || 0).to_f.clamp(0.0, 1.0)

def flylo_duck_split
  FLYLO_HAT_DUCK.positive? ? ",asplit=2[sub][subkey]" : "[sub]"
end

def flylo_duck_apply
  return "[top]" unless FLYLO_HAT_DUCK.positive?

  d = FLYLO_HAT_DUCK
  # Threshold high, release short. At 0.056 this triggered on anything in the
  # kick bus above about -25 dBFS, which is most of the time, so it behaved as a
  # general compressor on the top bus rather than as a duck -- measured, cymbals
  # lost 2.3 dB in the gaps BETWEEN kicks, where a sidechain should do nothing
  # whatsoever. A duck has to be deaf to everything except the transient.
  #
  # Release also has to finish inside a 16th (183ms at 82 BPM) or the recovery
  # from one kick is still in progress when the next 16th arrives, which is the
  # same fault by a slower route.
  "[topraw];[topraw][subkey]sidechaincompress=" \
    "threshold=#{(0.35 - (0.12 * d)).round(4)}:ratio=#{(2.0 + (6.0 * d)).round(1)}:" \
    "attack=#{(4.0 - (2.5 * d)).round(1)}:release=#{(90 - (40 * d)).round}:" \
    "makeup=1[top]"
end

# A bed of room noise under the kit, ducked by the kit itself.
#
# The point is not that the noise is audible -- it should not be, on its own.
# It is that continuous low-level room behind the drums removes the silence
# between hits, and silence between hits is what makes programmed drums sound
# programmed. Ducking it by the kit keeps it from crowding the transients it is
# there to support.
#
# Sources come from the synthesised crate, so this needs no field recording and
# no external file. `ruby dilla.rb crate` builds them.
DRUM_FIELD_LAYER = ENV["DRUM_FIELD_LAYER"].to_s
DRUM_FIELD_MIX = (ENV["DRUM_FIELD_MIX"] || 0.18).to_f.clamp(0.0, 1.0)

def drum_field_layer!(drum_path, duration:)
  return drum_path if DRUM_FIELD_LAYER.empty? || !File.file?(drum_path)

  src = File.join(CRATE_DIR, "texture_#{DRUM_FIELD_LAYER}.wav")
  unless File.file?(src)
    warn "drum field: no texture_#{DRUM_FIELD_LAYER}.wav in the crate — run `ruby dilla.rb crate`"
    return drum_path
  end

  out = "#{drum_path}.field.wav"
  begin
    sh! "ffmpeg", "-y", "-i", drum_path, "-stream_loop", "-1", "-i", src,
        "-filter_complex",
        "[0:a]asplit=2[dry][key];" \
        "[1:a]volume=#{DRUM_FIELD_MIX},atrim=0:#{duration.round(3)}," \
        "apad=whole_dur=#{duration.round(3)}[bed];" \
        "[bed][key]sidechaincompress=threshold=0.25:ratio=6:attack=3:release=110:makeup=1[ducked];" \
        "[dry][ducked]amix=inputs=2:duration=first:normalize=0[out]",
        "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
        "-c:a", "pcm_s16le", out
    FileUtils.mv(out, drum_path)
    dmesg("drum field: #{DRUM_FIELD_LAYER} under the kit at #{DRUM_FIELD_MIX}, ducked",
          unit: "drum0", parent: "dilla0")
    drum_path
  rescue StandardError => e
    warn "drum field: #{e.message}"
    FileUtils.rm_f(out)
    drum_path
  end
end

def merge_flylo_dual_bus!(drum_path, sub_path, top_path)
  unless File.file?(drum_path)
    warn "flylo merge: missing drum bus — skipping overlay"
    return
  end
  unless File.file?(sub_path) && File.file?(top_path)
    warn "flylo merge: overlay bus missing (sub=#{File.file?(sub_path)} top=#{File.file?(top_path)}) — skipping"
    return
  end
  merged = "#{drum_path}.merged.#{Process.pid}.wav"
  boost = ENV.fetch("FLYLO_MERGE_BOOST", flylo_primary_drums? ? "1.85" : "1.22").to_f
  sub_vol = (ENV.fetch("FLYLO_SUB_MIX", flylo_primary_drums? ? "1.05" : "0.38").to_f * boost).round(3)
  top_vol = (ENV.fetch("FLYLO_TOP_MIX", flylo_primary_drums? ? "0.88" : "0.32").to_f * boost).round(3)
  # Empty pocket base under FlyLo-only — don't pad-mix silence that dilutes the kit.
  base_vol = ENV.fetch("FLYLO_BASE_DRUM_VOL", flylo_primary_drums? ? "0.15" : "1.0").to_f.round(3)
  # Sub bus used to lowpass @ 220Hz and kill kick click/body (150Hz+beater).
  # Keep boom + mid punch so kicks read on laptop speakers.
  sh! "ffmpeg", "-y", "-i", drum_path, "-i", sub_path, "-i", top_path,
      "-filter_complex",
      "[0:a]volume=#{base_vol}[base];" \
      "[1:a]highpass=f=28,lowpass=f=520,equalizer=f=55:t=o:w=0.75:g=6.5," \
      "equalizer=f=110:t=o:w=1.0:g=4.0,equalizer=f=180:t=o:w=1.1:g=3.0," \
      "volume=#{sub_vol}#{flylo_duck_split};" \
      "[2:a]#{flylo_top_dirt}highpass=f=700,equalizer=f=3500:t=o:w=1.3:g=5.5," \
  "equalizer=f=6500:t=o:w=1.4:g=6.5,equalizer=f=9000:t=h:w=1.2:g=4.0," \
  "volume=#{top_vol}#{flylo_duck_apply};" \
      "[base][sub][top]amix=inputs=3:duration=first:normalize=0," \
      "alimiter=limit=0.97:level_out=0.98",
      "-c:a", "pcm_s16le", merged
  FileUtils.mv(merged, drum_path)
end

# DRUM_VOL looks like the kit fader and is what stream_iterate / composition
# mutate. The main render reads DRUM_MIX_WEIGHT. Treat an explicit DRUM_VOL as
# the mix weight when DRUM_MIX_WEIGHT was not pinned, so those writers move
# the bus they think they are moving.
def resolved_drum_mix_weight
  mix = ENV["DRUM_MIX_WEIGHT"]
  vol = ENV["DRUM_VOL"]
  pinned_mix = USER_PINNED_ENV["DRUM_MIX_WEIGHT"]
  pinned_vol = USER_PINNED_ENV["DRUM_VOL"]
  return pinned_vol.to_f if pinned_vol && pinned_mix.to_s.empty?
  return mix.to_f if mix && !mix.empty?

  (vol.nil? || vol.empty? ? 0.88 : vol).to_f
end

def apply_drum_vol!(value)
  s = value.to_f.round(2).to_s
  ENV["DRUM_VOL"] = s
  ENV["DRUM_MIX_WEIGHT"] = s
  s
end

def drum_drop_enabled?
  ENV.fetch("DRUM_DROP", "1") != "0"
end

def drum_drop_bar?(bar, section)
  return false unless drum_drop_enabled?
  return true if section == :breakdown && bar % 8 == 0
  bar.positive? && bar % 32 == 31
end

def drum_bus_mapping
  # Bass/sub stay on the harmonic bus only — routing them here too doubled
  # the low end on every kick and buried the pad chords in the mix.
  map = {
    snare: :snare, ghost: :ghost, hat: :hat, open: :open_hat,
    poly: :ghost, shaker: :shaker, cowbell: :cowbell,
    poly5: :rim, clap: :clap, rim: :rim, glitch: :ind_stab, tabla: :tabla,
    tambourine: :tambourine, woodblock: :woodblock, agogo: :agogo,
  }
  map[:kick] = :kick if kicks_enabled?
  map
end

# Where the pad bus rolls off.
#
# 3400 Hz had no override of any kind -- it came from the sonic profile or that
# literal, so there was no way to test a brighter pad without editing profiles.
#
# Measured against three J Dilla records (Time: The Donut of the Heart, Slum
# Village's World Full of Sadness, Jay Dee's La La La), octave-band energy
# relative to each file's own full-band level:
#
#            125Hz  250   500    1k    2k    4k    8k    tilt 125->4k
#   Time      -5.8  -8.1 -10.5 -11.9 -11.4 -15.1 -20.7   -1.86 dB/oct
#   Sadness   -3.5  -8.9 -12.7 -14.7 -15.9 -17.1 -19.6   -2.72
#   La La La  -2.2  -9.0 -14.4 -15.7 -16.1 -15.2 -17.5   -2.60
#   engine    -3.1  -5.1 -10.0 -15.1 -21.2 -27.5 -32.8   -4.88
#
# The engine falls roughly twice as fast: 12 dB darker at 4 kHz and 12-15 dB at
# 8 kHz than any of the three. It also carries 3-4 dB MORE at 250 Hz. Dark and
# congested at once, which is what "overdrive sound, pads not nice" describes.
#
# Caveat kept deliberately: the engine figure is an instrumental 8-bar sketch
# and the records are full mastered tracks with vocals and leads that carry
# their own top end. A render WITH a rap vocal measures -3.66 dB/oct -- closer,
# still steeper than all three. So content explains part of the gap and not all
# of it.
#
# The default is unchanged at 3400. PAD_LP exists so the number can be tested
# against those references instead of argued about; moving the default is a tone
# decision and belongs to the operator.
#
# A/B'd immediately after adding it, and the answer was NOT what the comment
# above would lead you to expect: PAD_LP=3400 against PAD_LP=7000 produces
# different files (different checksums, the override is definitely read) whose
# octave-band energy is identical to 0.1 dB at every band. The pad bus
# does not carry enough of the mix's top end for its bandwidth to register.
#
# So the darkness is not here. What the same measurement did find: every sampled
# bed is lowpassed between 5200 and 6000 Hz by its TRACK_SAMPLE_LOOPS entry,
# while all three reference records hold real energy at 8 kHz (-17.5 to -20.7
# relative). And the source material can carry it -- kembara_rindu's own loop.wav
# measures -2.54 dB/oct with 4 kHz at -17.8, which is La La La's -2.60 and -15.2
# almost exactly. The crates are not the limit; the per-loop lp is.
def sonic_pad_lowpass(sonic)
  pinned = ENV["PAD_LP"].to_s.strip
  return pinned.to_i.clamp(800, 18_000) if pinned =~ /\A\d+\z/

  sonic&.dig("synth", "pad_lowpass_hz")&.to_i || 3400
end

def sonic_vinyl_level(sonic)
  # VINYL=0 disables the pink-noise bed. VINYL=1..100 scales intensity (default ~35 → mild).
  if ENV.key?("VINYL")
    v = ENV["VINYL"].to_f
    return 0.0 if v <= 0
    return (v / 100.0 * 0.18).clamp(0.0, 0.12).round(3)
  end
  sonic&.dig("synth", "vinyl_noise")&.to_f || 0.08
end
