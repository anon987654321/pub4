# frozen_string_literal: true
#
# Bus filter chains: analog colour, bass, harmony, sidechain and bridges.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# The bass gets its own bus rather than riding the harmonic one. It used to be
# mixed into the harmonic render, which is high-passed to keep pad mud out of
# the kick's way -- and that corner sits ABOVE the bass fundamental (roots land
# at 82-116 Hz), so the bass was filtered out of the mix it was supposed to
# anchor. That is also why the earlier attempts to fix it by raising BASS_VOL
# and lowering the harm corner never moved the master: the level was never the
# problem, the routing was. The engine's own quality gate had been rejecting
# every take on "sub=boost_sub (low-mid -9.51 dB)" because of it.
# Per-channel analog treatment, applied BEFORE the buses are summed.
#
# The master already runs sonitex tape and an analog chain, but that stage only
# ever sees the sum. A desk does not work that way: every channel saturates on
# the way in, so each source generates its own harmonics first and those
# harmonics then intermodulate in the bus. One saturator on the sum cannot
# produce that, because by the time it runs the sources no longer exist
# separately.
#
# Character differs per bus because the sources do. Drums take the hardest
# drive -- transients are what saturation flatters. Bass takes the least: it is
# already the loudest thing in the low end and driving it turns definition into
# mud. Harmony sits between, where a little bloom thickens pads without
# blurring their attacks.
# 0.18. Per-bus colour plus the small phase offsets below, so the buses do not
# sum perfectly coherently. Off by default meant every bus summed like maths.
BUS_ANALOG = (ENV["BUS_ANALOG"] || 0.18).to_f.clamp(0.0, 1.0)

BUS_ANALOG_CHARACTER = {
  drums: { drive: 1.0, tilt: 2.2, hz: 3200 },
  bass:  { drive: 0.45, tilt: 0.8, hz: 900 },
  harm:  { drive: 0.7, tilt: 1.4, hz: 2400 },
}.freeze

# Small per-bus phase offsets so the buses do not sum perfectly coherently.
# Real summing is never phase-aligned -- each channel takes a slightly different
# path -- and that incoherence is most of what "phasy summing" means. The
# offsets are tiny and fixed: large ones comb-filter, and random ones make a
# render unreproducible.
BUS_PHASE_MS = { drums: 0.0, bass: 0.35, harm: 0.62 }.freeze

def bus_analog_filter(bus)
  return "" if BUS_ANALOG <= 0.0

  c = BUS_ANALOG_CHARACTER.fetch(bus)
  d = BUS_ANALOG * c[:drive]
  phase = BUS_PHASE_MS.fetch(bus) * BUS_ANALOG
  parts = []
  # Drive hard, clip low, then take the level back out.
  #
  # The first version drove by 1.44x into a threshold of 0.76 and measured as
  # doing nothing at all -- because an individual bus peaks far below the summed
  # mix, so a threshold set for master levels is never reached and the clipper
  # never engages. A saturator that never saturates is just a gain stage with a
  # misleading name. Threshold now scales DOWN with drive so the harder it is
  # pushed the sooner it bites, which is what the control is supposed to mean.
  # alimiter, not asoftclip. Tested on a clean 200 Hz sine, where any energy
  # above 500 Hz can only be harmonics the stage invented: asoftclip produced
  # -40.8 dB against -40.1 dB clean, which is nothing, at any threshold tried.
  # acrusher likewise. Drive into a low limiter ceiling gives -19.1 dB, i.e. 21
  # dB of genuine harmonic content. Two earlier attempts here failed because
  # they tuned the parameters of a filter that was transparent to begin with --
  # the primitive was wrong, not the settings.
  drive = 1.0 + (2.2 * d)
  parts << "volume=#{drive.round(3)}"
  parts << "alimiter=limit=#{(0.45 - (0.28 * d)).round(3)}:level_out=1:attack=1:release=20"
  parts << "volume=#{(1.0 / (1.0 + (2.2 * d))).round(3)}"
  # Tape tilt: a little lift where the source lives, gentle roll above it.
  parts << "equalizer=f=#{c[:hz]}:t=o:w=1.4:g=#{(c[:tilt] * d).round(2)}"
  parts << "adelay=#{(phase * 1000).round}|#{((phase * 1000) * 1.3).round}" if phase.positive?
  "#{parts.join(',')},"
end

def build_bass_bus_filter(idx, duration)
  vol = ENV.fetch("BASS_BUS_VOL", "1.4").to_f
  sub_g = ENV.fetch("BASS_BUS_SUB_DB", "3.0").to_f
  mud_g = ENV.fetch("BASS_BUS_MUD_DB", "-1.5").to_f
  "[#{idx}:a]aformat=channel_layouts=stereo,#{bus_analog_filter(:bass)}volume=#{vol}," \
    "highpass=f=26," \
    "equalizer=f=70:t=o:w=1.1:g=#{sub_g}," \
    "equalizer=f=180:t=o:w=1.2:g=#{mud_g}," \
    # The Pultec move on top of the two bands above: a broad lift under 100 Hz
    # and a narrower dip near 280 -- the shape no single control produces, and
    # the reason a fifty-year-old passive equaliser is still on every low end.
    # Measured at +3.7 dB and -1.9 dB, flat again by a kilohertz.
    "#{Outboard.pultec_low}," \
    "lowpass=f=1400," \
    "acompressor=threshold=-20dB:ratio=2.4:attack=14:release=150:makeup=1.5," \
    "atrim=0:#{duration},apad=whole_dur=#{duration}," \
    "alimiter=limit=0.95:level_out=0.97[bassbus]"
end

# The Space Echo on the pads.
#
# Two of them sit in Flying Lotus's studio and it is on a great deal of what he
# has made. On a chord bed it does something no reverb does: the repeats are
# darker and less steady than the source, so the pad trails off into something
# that is recognisably the same chord and recognisably older than it. That is
# the depth in his records, and it is a delay rather than a reverb doing it.
#
# On the pads only. Through the drums it smears the transients the kit exists
# for, and on the bass it muddies the octave the Pultec was just cleaning.
def harm_space_echo
  return nil unless ENV.fetch("SPACE_ECHO", "1") != "0"

  Outboard.space_echo(time_ms: ENV.fetch("SPACE_ECHO_MS", "240").to_f,
                      feedback: ENV.fetch("SPACE_ECHO_FB", "0.45").to_f,
                      mix: ENV.fetch("SPACE_ECHO_MIX", "0.3").to_f)
end

def build_harm_bus_filter(idx, duration, _cfg, sonic, harm_fade_start, harm_fade_dur, beat_p, _n_bars)
  lp = sonic_pad_lowpass(sonic)
  build_start = (duration * 0.82).round(2)
  # 16 beats, but never longer than the render itself — short (preview/smoke)
  # renders would otherwise produce a negative afade start, which ffmpeg
  # rejects as out of range.
  outro_fade = [(beat_p * 4.0 * 4).round(2), duration].min
  # Pads are the character of the stream — keep them warm and present.
  # Kick space is a gentle HP + sidechain, not stripping pad body (165 Hz HP
  # + −5.5 dB sub cut made progressions inaudible).
  default_vol = if flylo_primary_drums?
                  "1.72"
                elsif deep_render?
                  "1.82"
                else
                  "1.68"
                end
  harm_vol = ENV["DEBUG_HARM_WEIGHT"] || ENV.fetch("HARM_BUS_VOL", default_vol)
  deep = deep_render?
  sub_cut = ENV.fetch("HARM_SUB_CUT_DB", if deep
"-1.8"
else
(flylo_primary_drums? ? "-2.4" : "-2.2")
end)
  body_boost = ENV.fetch("HARM_BODY_DB", if deep
"3.2"
else
(flylo_primary_drums? ? "2.6" : "2.8")
end)
  mid_boost = ENV.fetch("HARM_MID_DB", if deep
"2.9"
else
(flylo_primary_drums? ? "2.4" : "2.6")
end)
  # Chord presence: body + gentle silk shelf (progressions read on small speakers).
  # HARM_PRESENCE_DB / HARM_AIR_DB are crit cherry-pick knobs (defaults keep prior character).
  presence = ENV.fetch("HARM_PRESENCE_DB", flylo_primary_drums? ? "2.2" : "2.4").to_f
  air_g = ENV.fetch("HARM_AIR_DB", flylo_primary_drums? ? "1.6" : "1.2").to_f
  silk_g = flylo_primary_drums? ? [presence * 0.9, 2.0].min : [presence * 0.55, 1.2].min
  air = if flylo_primary_drums?
          "equalizer=f=2400:t=h:w=1800:g=#{silk_g.round(1)},equalizer=f=5200:t=h:w=2800:g=#{air_g.round(1)},"
        else
          "equalizer=f=2800:t=h:w=1800:g=#{air_g.round(1)},"
        end
  # The synthesised bass rides this bus, and its roots land at 82-116 Hz
  # (E2 for the Get Dis Money pedal). A 110 Hz corner cut the bass fundamental
  # straight out of the mix, which is why the track had no low end -- and why
  # the old hz.min bass bug went unnoticed for so long: playing the wrong note
  # up at 165-208 Hz was the only way the bass got past this filter at all.
  # Pads cannot be hurt by opening it up: measured across every track, the
  # lowest voiced pad tone is 164-247 Hz, so nothing pad-side lives below the
  # old corner. Kept high enough to still shed sub rumble.
  harm_hp = ENV.fetch("HARM_HP_HZ", if deep
"66"
else
(flylo_primary_drums? ? "68" : "70")
end).to_i
  sub_shelf = ENV.fetch("HARM_SUB_SHELF_DB", if deep
"2.2"
else
(flylo_primary_drums? ? "1.8" : "1.0")
end).to_f
  # Longer, smoother pad bloom (qsin) so chords arrive as wash, not a gate.
  fade_in = flylo_primary_drums? ? (harm_fade_dur * 1.35).round(2) : harm_fade_dur
  fade_curve = flylo_primary_drums? ? ":curve=qsin" : ""
  build_cut = flylo_primary_drums? ? -0.8 : -2
  "[#{idx}:a]aformat=channel_layouts=stereo,volume=#{harm_vol}," \
    "highpass=f=#{harm_hp},equalizer=f=72:t=o:w=1.2:g=#{sub_shelf}," \
    "equalizer=f=95:t=h:w=120:g=#{sub_cut}," \
    "equalizer=f=420:t=o:w=1.1:g=#{body_boost},equalizer=f=680:t=h:w=900:g=#{mid_boost}," \
    "equalizer=f=1400:t=h:w=1200:g=#{presence}," \
    "#{air}equalizer=f=#{lp}:t=o:w=1.0:g=0.8," \
    "afade=t=in:st=#{harm_fade_start}:d=#{fade_in}#{fade_curve}," \
    "afade=t=out:st=#{(duration - outro_fade).round(2)}:d=#{outro_fade}#{fade_curve}," \
    "equalizer=f=800:t=h:w=600:g=#{build_cut}:enable='between(t,#{build_start},#{duration})'" \
    "#{harm_space_echo ? "[harm_pre];[harm_pre]#{harm_space_echo}[harm]" : '[harm]'}"
end

def sidechain_amix_weights
  # Camel: pads duck under kicks but stay the main body (not 2.05:0.78 — that
  # erased chord progressions). Kit still leads the transient.
  d = ENV.fetch("SIDECHAIN_DRUM_WEIGHT", flylo_primary_drums? ? "1.48" : "1.0").to_f
  h = ENV.fetch("SIDECHAIN_HARM_WEIGHT", flylo_primary_drums? ? "1.32" : "1.55").to_f
  [d.round(3), h.round(3)]
end

def flylo_sidechain_filters(drum_label: "[drums]", harm_label: "[harm]")
  dw, hw = sidechain_amix_weights
  # Musical duck: soft attack + longer release so pads bloom back between kicks
  # (was attack=1/release=28 — choppy, made progressions feel gated).
  atk = flylo_primary_drums? ? 8 : 1
  rel = flylo_primary_drums? ? 140 : 28
  ratio = flylo_primary_drums? ? 3.2 : 5
  thr = flylo_primary_drums? ? -22 : -20
  [
    "#{drum_label}asplit=2[dr_dry][dr_sc]",
    "#{harm_label}[dr_sc]sidechaincompress=threshold=#{thr}dB:ratio=#{ratio}:attack=#{atk}:release=#{rel}:level_sc=0.9[harm_sc]",
    "[dr_dry][harm_sc]amix=inputs=2:weights=#{dw} #{hw}:duration=first:normalize=0[sc_mix]",
  ]
end

# Tight kick-triggered duck — short attack/release for MPC pocket, not wash.
def dilla_sidechain_filters(drum_label: "[drums]", harm_label: "[harm]")
  dw, hw = sidechain_amix_weights
  [
    "#{drum_label}asplit=2[dr_dry][dr_sc]",
    "#{harm_label}[dr_sc]sidechaincompress=threshold=-24dB:ratio=5:attack=0.3:release=90:level_sc=0.88[harm_sc]",
    "[dr_dry][harm_sc]amix=inputs=2:weights=#{dw} #{hw}:duration=first:normalize=0[sc_mix]",
  ]
end

# Puts the kit in front by moving the sample out of its way, band by band.
#
# The sampled bed joined the master mix undicked, at full bandwidth, while the
# kit sat behind it. A record and a drum kit occupy the same frequencies -- the
# record HAS drums in it, or had them until demucs took them out, and it still
# has the room they were played in. Two full-range signals in one place is what
# a muddy mix is.
#
# Turning the kit up is the wrong repair: it makes a loud muddy mix. Instead the
# bed is split into three bands and only two of them move.
#
#   below 180 Hz   ducks hard when the kick lands. Nothing else may be there.
#   180 Hz - 3 kHz untouched. This is the body of the record, the reason the
#                  track exists, and it is not where drums need clarity.
#   above 3 kHz    ducks lightly on the snare and hats, which is what "crisp"
#                  actually means -- room at the top for the transient.
#
# Each band is keyed by the drums filtered to that same band, so the low band
# responds to kicks and not to hats. The result is a kit that reads clearly
# through a bed that still sounds whole.
DRUM_FORWARD_SPLIT = [180, 3000].freeze

def drum_forward_filters(bed: "[loopbed]", key: "[dr_key]", out: "[bedcarved]")
  low_thr = ENV.fetch("DRUM_FORWARD_LOW_DB", "-30")
  air_thr = ENV.fetch("DRUM_FORWARD_AIR_DB", "-26")
  [
    # One key signal per band that ducks, filtered to hear only its own drums.
    "#{key}asplit=2[dk_lo][dk_hi]",
    "[dk_lo]lowpass=f=#{DRUM_FORWARD_SPLIT[0]}[dkl]",
    "[dk_hi]highpass=f=#{DRUM_FORWARD_SPLIT[1]}[dkh]",
    "#{bed}acrossover=split=#{DRUM_FORWARD_SPLIT.join(' ')}:order=4th[bd_lo][bd_mid][bd_hi]",
    # Fast attack on the low band: the kick's first cycle is the whole point, and
    # a slow attack lets the bed's own bass through underneath it.
    "[bd_lo][dkl]sidechaincompress=threshold=#{low_thr}dB:ratio=8:attack=1:release=120:level_sc=1.0[bd_lo_sc]",
    # Gentler and quicker up top: this is opening a window for a transient, not
    # pumping. A long release here would breathe audibly on every hat.
    "[bd_hi][dkh]sidechaincompress=threshold=#{air_thr}dB:ratio=4:attack=0.4:release=55:level_sc=1.0[bd_hi_sc]",
    "[bd_lo_sc][bd_mid][bd_hi_sc]amix=inputs=3:weights=1 1 1:duration=first:normalize=0#{out}",
  ]
end

# Sharpens the kit without raising it.
#
# A compressor with a SLOW attack is the transient shaper nobody names as one:
# by the time it clamps down, the stick hit has already passed through
# untouched, and what it compresses is the body behind it. The attack therefore
# stands further above its own tail than it did going in. That is "crisper", and
# it costs no headroom, unlike simply turning the drums up.
#
# The shelf above 7 kHz is the stick and the hat sizzle. Small: this is a lo-fi
# engine and 3 dB of air is the difference between dull and modern, while 8 dB
# is the difference between modern and cheap.
def drum_crisp_chain
  return nil if ENV["DRUM_CRISP"] == "0"

  attack = ENV.fetch("DRUM_CRISP_ATTACK", "22")
  air = ENV.fetch("DRUM_CRISP_AIR_DB", "3")
  "acompressor=threshold=-18dB:ratio=4:attack=#{attack}:release=70:makeup=1.6," \
    "treble=g=#{air}:f=7000:width_type=q:width=0.7"
end

# Joins one section of the record to the next the way a producer would.
#
# A looped sample restated every four bars announces itself as a loop. What
# stops it is a gesture in the last beat before the turnover -- something that
# takes the ear off the seam. Dilla's records are full of these and they are not
# subtle when you look for them: the filter shuts for half a beat and snaps
# open on the one; everything drops out and the record plays naked; the whole
# thing swells up from nothing into the downbeat.
#
# Three treatments, chosen per boundary from the track name so a given track
# always bridges the same way:
#
#   :sweep    the lowpass closes over the last beat and opens on the downbeat.
#             The most common of the three because it is the least tiring.
#   :dropout  the bed cuts for the back half of the last beat. Silence is a
#             transition. This is the one that makes the return feel like an
#             arrival.
#   :swell    the bed rises from near nothing across the last bar, so the
#             downbeat is the top of a ramp rather than a restart.
#
# Sweeps run through asendcmd rather than an expression because lowpass takes
# its cutoff as a runtime command, not a per-frame formula -- twelve stepped
# commands per boundary, geometrically spaced, which the ear reads as a glide.
BRIDGE_KINDS = %i[sweep dropout swell sweep].freeze
BRIDGE_SWEEP_STEPS = 12
BRIDGE_OPEN_HZ = 16_000
BRIDGE_CLOSED_HZ = 320

def bridge_plan(n_bars, bar_sec, track, every_bars)
  return [] if every_bars < 1 || n_bars <= every_bars

  rng = Random.new(stable_hash("bridge:#{track}"))
  # Boundaries are the downbeats between sections. The final bar has no section
  # after it, so it gets no bridge -- a gesture into silence is just a fade.
  (every_bars...n_bars).step(every_bars).map do |bar|
    { at: (bar * bar_sec).round(4), kind: BRIDGE_KINDS[rng.rand(BRIDGE_KINDS.length)] }
  end
end

def bridge_filters(input:, output:, n_bars:, bar_sec:, track:, every_bars: 4)
  plan = bridge_plan(n_bars, bar_sec, track, every_bars)
  return ["#{input}anull#{output}"] if plan.empty?

  beat = bar_sec / 4.0
  cmds = []
  gates = []
  plan.each do |b|
    case b[:kind]
    when :sweep
      # Close across the last beat, then reopen exactly on the downbeat. The
      # reopen is a single command, not a ramp: the snap is the effect.
      BRIDGE_SWEEP_STEPS.times do |i|
        frac = (i + 1).to_f / BRIDGE_SWEEP_STEPS
        hz = (BRIDGE_OPEN_HZ * ((BRIDGE_CLOSED_HZ.to_f / BRIDGE_OPEN_HZ)**frac)).round
        cmds << "#{(b[:at] - beat + (beat * frac)).round(4)} lowpass frequency #{hz}"
      end
      cmds << "#{b[:at].round(4)} lowpass frequency #{BRIDGE_OPEN_HZ}"
    when :dropout
      gates << "between(t,#{(b[:at] - (beat * 0.5)).round(4)},#{b[:at].round(4)})*1"
    when :swell
      # A quarter-power curve rather than a straight line: linear ramps in
      # amplitude are heard as back-loaded, since loudness follows the log.
      gates << "between(t,#{(b[:at] - bar_sec).round(4)},#{b[:at].round(4)})*" \
               "(1-pow((t-#{(b[:at] - bar_sec).round(4)})/#{bar_sec.round(4)},0.25))"
    end
  end

  # One volume expression for every dip in the track. Each term is zero outside
  # its own window, so summing them and subtracting from 1 gives full level
  # everywhere a bridge is not happening.
  duck = gates.empty? ? nil : "volume='max(0,1-(#{gates.join('+')}))':eval=frame"
  stages = ["lowpass=f=#{BRIDGE_OPEN_HZ}"]
  stages.unshift("asendcmd='#{cmds.join('; ')}'") unless cmds.empty?
  stages << duck if duck
  ["#{input}#{stages.join(',')}#{output}"]
end
