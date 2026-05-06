#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Sirkel Sag × Voicemails — mix builder + sample harvester.
#
# Mix:
#   ruby make.rb [v7|v8|v9|v10|v11]            default: v11
# Sample harvest (YouTube → stems):
#   ruby make.rb demux <url-or-path>           6-stem demucs
#   ruby make.rb demux <url-or-path> deep      6-stem + EQ sub-bands + M/S
# Standalone beat synthesizers (no source needed):
#   ruby dilla_hiphop.rb [out.mp3]             86 BPM × 8 bars, lo-fi
#   ruby techno_hate.rb [out.mp3]              142 BPM × 8 bars, distorted
#
# v7   Dilla × FlyLo × Afta-1 base, heavy master + vinyl crackle
# v8   Dilla Drunk — sub-forward, dry vox, wobble
# v9   Afta-1 Psychedelic Space — pitch -4st, slowed 8%, Db-min pad
# v10  Crane Song HEDD — triode/pentode harmonic emulation, C-min pad
# v11  Clean & Soothing — 2kHz pluck notch, M/S split, original-pitch vox

require "fileutils"

DIR  = __dir__
BEAT = ENV.fetch("BEAT", "/sdcard/Download/Voicemails.mp3")
DUR  = 146
BPM  = 118.6

VOCALS = {
  processed: File.join(DIR, "vocals_processed.wav"),
  precise:   File.join(DIR, "vocals_precise.wav"),
  original:  File.join(DIR, "vocals_original_pitch.wav"),
}.freeze

def out_path(ver)    = File.join(DIR, "final_mix_#{ver}.mp3")
def tmp(ver, name)   = "/tmp/#{ver}_#{name}.wav"
def loop_beat        = ["-stream_loop", "-1", "-i", BEAT, "-t", DUR.to_s]
def lavfi(src)       = ["-f", "lavfi", "-i", src]
def beat_ms(bpm)     = (60_000 / bpm).to_i
def dotted_8th(bpm)  = (beat_ms(bpm) * 0.75).to_i
def half(bpm)        = (beat_ms(bpm) * 2).to_i

def run(label, *cmd)
  puts ">>> #{label}"
  abort "fail: #{label}" unless system(*cmd.flatten.map(&:to_s))
end

def render(label, dest, inputs:, filter:, map:, args: ["-ar", "44100"])
  run label, "ffmpeg", "-y", *inputs,
      "-filter_complex", filter.tr("\n", " "),
      "-map", map, *args, dest
end

# ── v7 ────────────────────────────────────────────────────────────────────────
def v7
  ver = "v7"
  beat_pre, vocals_pre, crackle = tmp(ver, "beat"), tmp(ver, "vocals"), tmp(ver, "crackle")
  d8 = dotted_8th(BPM)

  render "beat: M/S + EQ + crunch + room", beat_pre,
    inputs: ["-i", BEAT], map: "[beat_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo,volume=1.0[raw];
      [raw]pan=stereo|c0=c0+c1|c1=c0+c1[mid];
      [raw]pan=stereo|c0=c0-c1|c1=c1-c0[side];
      [mid]equalizer=f=60:t=o:w=0.8:g=7,
           equalizer=f=120:t=o:w=1:g=3,
           equalizer=f=400:t=o:w=1:g=-2,
           equalizer=f=2000:t=o:w=2:g=-3,
           acompressor=threshold=-20dB:ratio=6:attack=2:release=80:makeup=3[mid_eq];
      [side]equalizer=f=300:t=o:w=2:g=-4,
            equalizer=f=6000:t=o:w=3:g=4,
            acompressor=threshold=-18dB:ratio=3:attack=8:release=120:makeup=2[side_eq];
      [mid_eq][side_eq]amix=inputs=2:weights=1.4 0.6[beat_mix];
      [beat_mix]acrusher=level_in=1.2:level_out=0.9:bits=14:mode=log:aa=1[beat_crush];
      [beat_crush]aecho=0.6:0.4:30|60|90:0.15|0.08|0.04[beat_room];
      [beat_room]acompressor=threshold=-16dB:ratio=4:attack=3:release=60:makeup=2[beat_comp];
      [beat_comp]volume=0.88[beat_out]
    F

  render "vocals: clear + shiny + precise", vocals_pre,
    inputs: ["-i", VOCALS[:processed]], map: "[voc_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
      [vraw]equalizer=f=180:t=o:w=1:g=-10,
            equalizer=f=300:t=o:w=1:g=-4,
            equalizer=f=900:t=o:w=1.5:g=2,
            equalizer=f=2500:t=o:w=2:g=5,
            equalizer=f=5000:t=o:w=2:g=4,
            equalizer=f=10000:t=o:w=3:g=5,
            equalizer=f=16000:t=o:w=3:g=4[voc_eq];
      [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=5:release=80:makeup=5[voc_comp];
      [voc_comp]asplit=4[va][vb][vc][vd];
      [va]volume=1.0[voc_dry];
      [vb]aecho=0.7:0.6:350|700:0.3|0.12,
          equalizer=f=300:t=h:w=1:g=0[voc_plate];
      [vc]adelay=#{d8}|#{d8 * 2},
          equalizer=f=400:t=h:w=1:g=0[voc_ping];
      [vd]chorus=0.5:0.9:20|25:0.1|0.08:0.15|0.2:1.0|1.0[voc_shimmer];
      [voc_dry][voc_plate][voc_ping][voc_shimmer]amix=inputs=4:weights=1.4 0.4 0.35 0.5[voc_wet];
      [voc_wet]volume=1.35[voc_out]
    F

  render "crackle: vinyl surface noise", crackle,
    inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.025:d=300"),
    map: "[crack_out]", filter: <<~F
      [0:a]equalizer=f=3000:t=o:w=3:g=5,
           equalizer=f=80:t=o:w=1:g=-15,
           volume=0.18[crack_out]
    F

  render "master: triple-comp + tape sat + limit", out_path(ver),
    inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle],
    map: "[out]", args: ["-b:a", "320k"], filter: <<~F
      [0:a]volume=0.82[b];
      [1:a]volume=1.25[v];
      [2:a]volume=0.22[c];
      [b][v][c]amix=inputs=3:duration=first:weights=1 1.25 0.22[raw_mix];
      [raw_mix]acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=3[comp_low];
      [comp_low]acompressor=threshold=-12dB:ratio=5:attack=2:release=60:makeup=3[comp_mid];
      [comp_mid]acompressor=threshold=-6dB:ratio=10:attack=1:release=30:makeup=2[comp_hi];
      [comp_hi]equalizer=f=55:t=o:w=0.7:g=5,
                equalizer=f=160:t=o:w=1:g=2,
                equalizer=f=500:t=o:w=1.5:g=-2,
                equalizer=f=3000:t=o:w=2:g=-1,
                equalizer=f=10000:t=o:w=2:g=3[master_eq];
      [master_eq]aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)'[tape_sat];
      [tape_sat]aecho=0.3:0.2:18:0.06[air];
      [air]alimiter=level_in=1.0:level_out=0.98:limit=0.92:attack=3:release=25:level=disabled[limited];
      [limited]volume=0.96[out]
    F
end

# ── v8 ────────────────────────────────────────────────────────────────────────
def v8
  ver = "v8"
  beat_pre, vocals_pre, crackle = tmp(ver, "beat"), tmp(ver, "vocals"), tmp(ver, "crackle")

  render "beat: sub focus + drunk wobble", beat_pre,
    inputs: loop_beat, map: "[beat_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
      [raw]equalizer=f=55:t=o:w=0.7:g=9,
           equalizer=f=120:t=o:w=1:g=4,
           equalizer=f=350:t=o:w=1.5:g=-6,
           equalizer=f=1000:t=o:w=2:g=-8,
           equalizer=f=4000:t=o:w=2:g=-5,
           equalizer=f=10000:t=o:w=3:g=-4[sub_heavy];
      [sub_heavy]acompressor=threshold=-18dB:ratio=8:attack=1:release=40:makeup=4[beat_comp];
      [beat_comp]tremolo=f=0.4:d=0.04[beat_wobble];
      [beat_wobble]acrusher=level_in=1.1:level_out=0.85:bits=16:mode=log:aa=1[beat_grit];
      [beat_grit]volume=0.75[beat_out]
    F

  render "vocals: dry + tight + present", vocals_pre,
    inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
      [vraw]equalizer=f=200:t=o:w=1:g=-10,
            equalizer=f=1200:t=o:w=2:g=3,
            equalizer=f=3000:t=o:w=2:g=6,
            equalizer=f=6000:t=o:w=2:g=4,
            equalizer=f=12000:t=o:w=3:g=3[voc_eq];
      [voc_eq]acompressor=threshold=-18dB:ratio=4:attack=3:release=60:makeup=6[voc_comp];
      [voc_comp]asplit=2[vd][vr];
      [vd]volume=1.0[voc_dry];
      [vr]aecho=0.5:0.3:80|160:0.12|0.05[voc_tiny_room];
      [voc_dry][voc_tiny_room]amix=inputs=2:weights=1.0 0.3[voc_out]
    F

  render "crackle: heavy vinyl", crackle,
    inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.05:d=#{DUR}"),
    map: "[crack_out]", filter: <<~F
      [0:a]equalizer=f=4000:t=o:w=3:g=8,
           equalizer=f=80:t=o:w=1:g=-20,
           volume=0.3[crack_out]
    F

  render "master: tape sat + breathe", out_path(ver),
    inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle],
    map: "[out]", args: ["-b:a", "320k"], filter: <<~F
      [0:a]volume=0.85[b];
      [1:a]volume=1.4[v];
      [2:a]volume=0.35[c];
      [b][v][c]amix=inputs=3:duration=first:weights=1 1.4 0.35[mix];
      [mix]equalizer=f=60:t=o:w=0.8:g=3,
           equalizer=f=5000:t=o:w=2:g=2[master_eq];
      [master_eq]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[tape];
      [tape]alimiter=level_in=1.0:level_out=0.97:limit=0.94:attack=5:release=80:level=disabled[out]
    F
end

# ── v9 ────────────────────────────────────────────────────────────────────────
def v9
  ver  = "v9"
  slow = 0.92
  bpm  = BPM * slow
  d8   = dotted_8th(bpm)
  hf   = half(bpm)
  beat_pre, vocals_pre, pad, crackle =
    tmp(ver, "beat"), tmp(ver, "vocals"), tmp(ver, "pad"), tmp(ver, "crackle")

  render "beat: pitched -4st + slowed + psychedelic", beat_pre,
    inputs: loop_beat, map: "[beat_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
      [raw]asetrate=44100*0.7937,aresample=44100,atempo=#{slow}[pitched];
      [pitched]equalizer=f=50:t=o:w=0.7:g=9,
               equalizer=f=100:t=o:w=1:g=5,
               equalizer=f=600:t=o:w=2:g=-3,
               equalizer=f=3000:t=o:w=2:g=-5[beat_eq];
      [beat_eq]aphaser=in_gain=0.6:out_gain=0.8:delay=4:decay=0.5:speed=0.4:type=triangular[beat_phase];
      [beat_phase]aecho=0.7:0.5:200|400:0.3|0.15[beat_echo];
      [beat_echo]acompressor=threshold=-16dB:ratio=5:attack=4:release=80:makeup=3[beat_comp];
      [beat_comp]volume=0.78[beat_out]
    F

  render "vocals: cathedral + shimmer + bitcrush + phaser", vocals_pre,
    inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
      [vraw]equalizer=f=150:t=o:w=1:g=-8,
            equalizer=f=800:t=o:w=2:g=2,
            equalizer=f=3000:t=o:w=2:g=3,
            equalizer=f=8000:t=o:w=3:g=5,
            equalizer=f=14000:t=o:w=3:g=4[voc_eq];
      [voc_eq]acompressor=threshold=-14dB:ratio=2.5:attack=8:release=200:makeup=5[voc_comp];
      [voc_comp]asplit=4[va][vb][vc][vd];
      [va]volume=0.9[voc_dry];
      [vb]aecho=0.88:0.92:800|1600|3200|6400:0.6|0.4|0.22|0.10[voc_cathedral];
      [vc]chorus=0.7:0.9:35|45|55:0.4|0.32|0.25:0.3|0.4|0.25:1.8|2.2|1.4[voc_shimmer];
      [vd]adelay=#{d8}|#{hf},
          acrusher=level_in=1.8:level_out=0.5:bits=6:mode=log:aa=1[voc_bit];
      [voc_dry][voc_cathedral][voc_shimmer][voc_bit]amix=inputs=4:weights=1 0.7 0.5 0.2[voc_wet];
      [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=3:decay=0.4:speed=0.2:type=sinusoidal[voc_phase];
      [voc_phase]flanger=delay=6:depth=5:speed=0.2:shape=sinusoidal[voc_flange];
      [voc_flange]volume=1.3[voc_out]
    F

  render "pad: Db minor sine chord swell", pad,
    inputs: lavfi("aevalsrc=0.12*sin(2*PI*138.59*t)+0.10*sin(2*PI*277.18*t)+0.08*sin(2*PI*349.23*t)+0.09*sin(2*PI*415.30*t)+0.05*sin(2*PI*554.37*t):s=44100:c=stereo:d=#{DUR}"),
    map: "[pad_out]", filter: <<~F
      [0:a]equalizer=f=800:t=o:w=2:g=-6,
           equalizer=f=3000:t=o:w=2:g=-10,
           aecho=0.9:0.85:600|1200:0.5|0.3[pad_echo];
      [pad_echo]chorus=0.6:0.8:40|50:0.3|0.25:0.4|0.3:1.5|2.0[pad_chorus];
      [pad_chorus]aphaser=in_gain=0.6:out_gain=0.8:delay=5:decay=0.6:speed=0.15:type=sinusoidal[pad_phase];
      [pad_phase]volume=0.22[pad_out]
    F

  render "crackle: distant vinyl", crackle,
    inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.02:d=#{DUR}"),
    map: "[crack_out]", filter: <<~F
      [0:a]equalizer=f=5000:t=o:w=3:g=6,
           equalizer=f=80:t=o:w=1:g=-18,
           volume=0.12[crack_out]
    F

  render "master: psychedelic space chain", out_path(ver),
    inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", pad, "-i", crackle],
    map: "[out]", args: ["-b:a", "320k"], filter: <<~F
      [0:a]volume=0.80[b];
      [1:a]volume=1.20[v];
      [2:a]volume=0.25[p];
      [3:a]volume=0.15[c];
      [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.2 0.25 0.15[mix];
      [mix]acompressor=threshold=-22dB:ratio=3:attack=8:release=200:makeup=3[comp1];
      [comp1]acompressor=threshold=-10dB:ratio=6:attack=2:release=60:makeup=2[comp2];
      [comp2]equalizer=f=50:t=o:w=0.7:g=4,
              equalizer=f=200:t=o:w=1:g=2,
              equalizer=f=2000:t=o:w=1.5:g=-2,
              equalizer=f=12000:t=o:w=2:g=3[master_eq];
      [master_eq]aeval='tanh(val(0)*3.0)/tanh(3.0)|tanh(val(1)*3.0)/tanh(3.0)'[tape];
      [tape]aecho=0.25:0.18:25:0.08[master_air];
      [master_air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=2:release=20:level=disabled[out]
    F
end

# ── v10 ───────────────────────────────────────────────────────────────────────
HEDD = "val(0)+0.28*val(0)*val(0)*(gt(val(0),0)-lt(val(0),0))+0.12*val(0)*val(0)*val(0)|" \
       "val(1)+0.28*val(1)*val(1)*(gt(val(1),0)-lt(val(1),0))+0.12*val(1)*val(1)*val(1)"

def v10
  ver = "v10"
  d8  = dotted_8th(BPM)
  beat_pre, vocals_pre, pad, crackle =
    tmp(ver, "beat"), tmp(ver, "vocals"), tmp(ver, "pad"), tmp(ver, "crackle")

  render "beat: HEDD triode+pentode + warmth", beat_pre,
    inputs: loop_beat, map: "[beat_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
      [raw]equalizer=f=50:t=o:w=0.8:g=6,
           equalizer=f=100:t=o:w=1:g=4,
           equalizer=f=250:t=o:w=1:g=2,
           equalizer=f=700:t=o:w=1.5:g=-1,
           equalizer=f=3000:t=o:w=2:g=1,
           equalizer=f=8000:t=o:w=2:g=2,
           equalizer=f=14000:t=o:w=3:g=3[beat_eq];
      [beat_eq]acompressor=threshold=-22dB:ratio=3:attack=15:release=200:makeup=3[tape_comp];
      [tape_comp]aeval='#{HEDD}'[hedd];
      [hedd]aecho=0.5:0.3:25|50:0.1|0.05[spring];
      [spring]volume=0.82[beat_out]
    F

  render "vocals: crystal + HEDD + wide stereo double", vocals_pre,
    inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
      [vraw]equalizer=f=160:t=o:w=1:g=-10,
            equalizer=f=350:t=o:w=1:g=-4,
            equalizer=f=1000:t=o:w=1.5:g=2,
            equalizer=f=2500:t=o:w=2:g=6,
            equalizer=f=5000:t=o:w=2:g=5,
            equalizer=f=10000:t=o:w=3:g=6,
            equalizer=f=16000:t=o:w=3:g=5[voc_eq];
      [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=6:release=100:makeup=5[voc_comp];
      [voc_comp]aeval='#{HEDD}'[voc_hedd];
      [voc_hedd]asplit=3[va][vb][vc];
      [va]volume=1.0[vdry];
      [vb]adelay=#{d8}|#{d8},
          aecho=0.65:0.55:400|800:0.35|0.15[vplate];
      [vc]chorus=0.5:0.9:18|22:0.08|0.06:0.2|0.25:1.0|1.0[vdouble];
      [vdry][vplate][vdouble]amix=inputs=3:weights=1.4 0.45 0.35[voc_out]
    F

  render "pad: C minor — warm soulful", pad,
    inputs: lavfi("aevalsrc=0.14*sin(2*PI*130.81*t)+0.11*sin(2*PI*261.63*t)+0.09*sin(2*PI*311.13*t)+0.10*sin(2*PI*392.00*t)+0.06*sin(2*PI*523.25*t):s=44100:c=stereo:d=#{DUR}"),
    map: "[pad_out]", filter: <<~F
      [0:a]equalizer=f=1000:t=o:w=2:g=-5,
           equalizer=f=4000:t=o:w=2:g=-10,
           equalizer=f=100:t=o:w=1:g=3[pad_eq];
      [pad_eq]aecho=0.85:0.8:500|1000:0.4|0.2[pad_echo];
      [pad_echo]chorus=0.5:0.8:35|45:0.25|0.2:0.35|0.25:1.2|1.6[pad_chorus];
      [pad_chorus]volume=0.18[pad_out]
    F

  render "crackle: light vinyl texture", crackle,
    inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.015:d=#{DUR}"),
    map: "[crack_out]", filter: <<~F
      [0:a]equalizer=f=4500:t=o:w=3:g=5,
           equalizer=f=80:t=o:w=1:g=-18,
           volume=0.10[crack_out]
    F

  render "master: HEDD bus + vintage tape + warm limit", out_path(ver),
    inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", pad, "-i", crackle],
    map: "[out]", args: ["-b:a", "320k"], filter: <<~F
      [0:a]volume=0.84[b];
      [1:a]volume=1.22[v];
      [2:a]volume=0.20[p];
      [3:a]volume=0.12[c];
      [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.22 0.20 0.12[mix];
      [mix]acompressor=threshold=-24dB:ratio=2:attack=20:release=300:makeup=2[glue];
      [glue]aeval='#{HEDD}'[bus_hedd];
      [bus_hedd]equalizer=f=45:t=o:w=0.7:g=3,
                 equalizer=f=150:t=o:w=1:g=2,
                 equalizer=f=700:t=o:w=1.5:g=-1,
                 equalizer=f=12000:t=o:w=2:g=2[master_eq];
      [master_eq]aeval='tanh(val(0)*2.2)/tanh(2.2)|tanh(val(1)*2.2)/tanh(2.2)'[tape_sat];
      [tape_sat]aecho=0.2:0.15:15:0.05[air];
      [air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=4:release=40:level=disabled[out]
    F
end

# ── v11 ───────────────────────────────────────────────────────────────────────
def v11
  ver = "v11"
  d8  = dotted_8th(BPM)
  beat_pre, vocals_pre, crackle = tmp(ver, "beat"), tmp(ver, "vocals"), tmp(ver, "crackle")

  render "beat: pluck notch + M/S + low-pass + phase sum", beat_pre,
    inputs: loop_beat, map: "[beat_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
      [raw]pan=stereo|c0=c0+c1|c1=c0+c1[mid];
      [raw]pan=stereo|c0=c0-c1|c1=c1-c0[side];
      [mid]lowpass=f=280[mid_bass];
      [mid_bass]equalizer=f=60:t=o:w=0.8:g=6,
                equalizer=f=120:t=o:w=1:g=3,
                acompressor=threshold=-18dB:ratio=6:attack=2:release=50:makeup=4[mid_punch];
      [side]equalizer=f=2000:t=o:w=0.8:g=-12,
            equalizer=f=2200:t=o:w=0.5:g=-8,
            lowpass=f=9000,
            equalizer=f=300:t=o:w=1:g=-3,
            equalizer=f=5000:t=o:w=2:g=2[side_clean];
      [side_clean]tremolo=f=0.35:d=0.05[side_wobble];
      [side_wobble]aphaser=in_gain=0.6:out_gain=0.8:delay=3:decay=0.4:speed=0.3:type=triangular[side_phase];
      [mid_punch][side_phase]amix=inputs=2:weights=1.3 0.7[beat_mix];
      [beat_mix]acompressor=threshold=-16dB:ratio=3:attack=5:release=100:makeup=2[beat_comp];
      [beat_comp]volume=0.82[beat_out]
    F

  render "vocals: original pitch + warm + soothing", vocals_pre,
    inputs: ["-i", VOCALS[:original]], map: "[voc_out]", filter: <<~F
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
      [vraw]equalizer=f=180:t=o:w=1:g=-8,
            equalizer=f=600:t=o:w=1.5:g=2,
            equalizer=f=2000:t=o:w=0.8:g=-6,
            equalizer=f=3000:t=o:w=2:g=5,
            equalizer=f=7000:t=o:w=2:g=4,
            equalizer=f=12000:t=o:w=3:g=2,
            lowpass=f=14000[voc_eq];
      [voc_eq]acompressor=threshold=-14dB:ratio=2.5:attack=8:release=150:makeup=5[voc_comp];
      [voc_comp]asplit=3[va][vb][vc];
      [va]volume=1.0[vdry];
      [vb]aecho=0.75:0.65:350|700:0.35|0.15[vplate];
      [vc]adelay=#{d8}|#{d8 * 2},
          chorus=0.5:0.8:20|25:0.08|0.06:0.2|0.25:1.0|1.0[vshine];
      [vdry][vplate][vshine]amix=inputs=3:weights=1.3 0.4 0.3[voc_wet];
      [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=2:decay=0.3:speed=0.25:type=sinusoidal[voc_phase];
      [voc_phase]volume=1.3[voc_out]
    F

  render "crackle: soft vinyl", crackle,
    inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.012:d=#{DUR}"),
    map: "[crack_out]", filter: <<~F
      [0:a]equalizer=f=5000:t=o:w=3:g=4,
           equalizer=f=80:t=o:w=1:g=-18,
           volume=0.10[crack_out]
    F

  render "master: warm + smooth + soothing", out_path(ver),
    inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle],
    map: "[out]", args: ["-b:a", "320k"], filter: <<~F
      [0:a]volume=0.85[b];
      [1:a]volume=1.25[v];
      [2:a]volume=0.12[c];
      [b][v][c]amix=inputs=3:duration=first:weights=1 1.25 0.12[mix];
      [mix]acompressor=threshold=-20dB:ratio=2.5:attack=18:release=250:makeup=3[glue];
      [glue]equalizer=f=55:t=o:w=0.8:g=4,
             equalizer=f=2000:t=o:w=0.6:g=-3,
             equalizer=f=8000:t=o:w=2:g=1,
             lowpass=f=16000[master_eq];
      [master_eq]aeval='tanh(val(0)*2.0)/tanh(2.0)|tanh(val(1)*2.0)/tanh(2.0)'[tape];
      [tape]aphaser=in_gain=0.3:out_gain=0.5:delay=2:decay=0.3:speed=0.15:type=sinusoidal[master_phase];
      [master_phase]alimiter=level_in=1.0:level_out=0.97:limit=0.93:attack=5:release=60:level=disabled[out]
    F
end

# ── demux ─────────────────────────────────────────────────────────────────────
# YouTube clip → 6-stem demucs → optional EQ sub-bands + M/S splits.
# Mirrors the band layout already in stems/ (sub_bass, mids, center, sides...).

DEMUX_DIR = File.join(DIR, "samples")
MODEL     = "htdemucs_6s"

def fetch_audio(src)
  return File.expand_path(src) unless src.match?(%r{\Ahttps?://})
  FileUtils.mkdir_p(DEMUX_DIR)
  base = "yt_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
  raw  = File.join(DEMUX_DIR, "#{base}.wav")
  run "yt-dlp #{src}", "yt-dlp", "-x", "--audio-format", "wav", "-o", raw, src
  raw
end

def demux_six(src)
  audio = fetch_audio(src)
  out   = File.join(DEMUX_DIR, "demux")
  FileUtils.mkdir_p(out)
  run "demucs #{MODEL}", "demucs", "-n", MODEL, "-o", out, audio
  stems = File.join(out, MODEL, File.basename(audio, ".*"))
  puts "stems -> #{stems}"
  stems
end

def slice_band(src, dest, label, eq:)
  render "band: #{label}", dest,
    inputs: ["-i", src], map: "[out]", filter: "[0:a]#{eq}[out]"
end

def demux_deep(src)
  stem_dir = demux_six(src)
  bands    = File.join(stem_dir, "bands")
  FileUtils.mkdir_p(bands)

  bass   = File.join(stem_dir, "bass.wav")
  drums  = File.join(stem_dir, "drums.wav")
  guitar = File.join(stem_dir, "guitar.wav")
  piano  = File.join(stem_dir, "piano.wav")
  other  = File.join(stem_dir, "other.wav")

  slice_band bass,  File.join(bands, "sub_bass.wav"),    "sub_bass",    eq: "lowpass=f=60"
  slice_band bass,  File.join(bands, "bass_mid.wav"),    "bass_mid",    eq: "highpass=f=60,lowpass=f=200"
  slice_band drums, File.join(bands, "kick.wav"),        "kick",        eq: "lowpass=f=100"
  slice_band drums, File.join(bands, "snare.wav"),       "snare",       eq: "highpass=f=200,lowpass=f=500"
  slice_band drums, File.join(bands, "hats.wav"),        "hats",        eq: "highpass=f=5000"
  slice_band other, File.join(bands, "mids.wav"),        "mids",        eq: "highpass=f=500,lowpass=f=2000"
  slice_band other, File.join(bands, "highs_pluck.wav"), "highs_pluck", eq: "highpass=f=2000,lowpass=f=5000"
  slice_band other, File.join(bands, "air.wav"),         "air",         eq: "highpass=f=5000"

  inst = File.join(bands, "instrumental.wav")
  render "instrumental sum", inst,
    inputs: ["-i", bass, "-i", drums, "-i", guitar, "-i", piano, "-i", other],
    map: "[out]", filter: "[0:a][1:a][2:a][3:a][4:a]amix=inputs=5:duration=longest[out]"

  slice_band inst, File.join(bands, "center.wav"), "center", eq: "pan=stereo|c0=c0+c1|c1=c0+c1"
  slice_band inst, File.join(bands, "sides.wav"),  "sides",  eq: "pan=stereo|c0=c0-c1|c1=c1-c0"

  puts "bands -> #{bands}"
end

# ── dispatch ──────────────────────────────────────────────────────────────────
RECIPES = { "v7" => method(:v7), "v8" => method(:v8), "v9" => method(:v9),
            "v10" => method(:v10), "v11" => method(:v11) }.freeze

case ARGV[0]
when "demux"
  src = ARGV[1] or abort "usage: ruby make.rb demux <url-or-path> [deep]"
  ARGV[2] == "deep" ? demux_deep(src) : demux_six(src)
when nil, /\Av\d+\z/
  ver = ARGV[0] || "v11"
  abort "unknown: #{ver}  have: #{RECIPES.keys.join(", ")}" unless RECIPES[ver]
  RECIPES[ver].call
  puts "done -> #{out_path(ver)}"
else
  abort "usage: ruby make.rb [v7|v8|v9|v10|v11]   ruby make.rb demux <url-or-path> [deep]"
end
