#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Mix v10 — "Crane Song Warmth" — HEDD harmonic enhancement emulation
# Triode mode = 2nd-order even harmonics (warmth/bottom)
# Pentode mode = 3rd-order odd harmonics (mid/upper-mid excitement)
# Tape compression feel, vintage spring reverb, crystal vocals, C minor pad.

BEAT   = "/sdcard/Download/Voicemails.mp3"
VOCALS = "/root/pub4/mix/vocals_precise.wav"
OUT    = "/root/pub4/mix/final_mix_v10.mp3"

BPM        = 118.6
BEAT_MS    = (60_000 / BPM).to_i
DOTTED_8TH = (BEAT_MS * 0.75).to_i

BEAT_PRE   = "/tmp/v10_beat.wav"
VOCALS_PRE = "/tmp/v10_vocals.wav"
PAD        = "/tmp/v10_pad.wav"
CRACKLE    = "/tmp/v10_crackle.wav"

def run(label, *cmd)
  puts "\n>>> #{label}"
  success = system(*cmd.flatten.map(&:to_s))
  abort "FAILED: #{label}" unless success
  puts "    OK"
end

# HEDD Triode emulation: even harmonics via x + 0.3*x^2 waveshaper
# HEDD Pentode emulation: odd harmonics via x + 0.15*x^3 waveshaper
# Combined: soft clip + harmonic richness without distortion
TRIODE_PENTODE = "val(0)+0.28*val(0)*val(0)*(gt(val(0),0)-lt(val(0),0))+0.12*val(0)*val(0)*val(0)|" \
                 "val(1)+0.28*val(1)*val(1)*(gt(val(1),0)-lt(val(1),0))+0.12*val(1)*val(1)*val(1)"

# Beat: warm harmonic enhancement, sub boost, vintage feel
run "Beat: HEDD triode+pentode + warmth",
  "ffmpeg", "-y",
  "-stream_loop", "-1", "-i", BEAT,
  "-t", "146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]equalizer=f=50:t=o:w=0.8:g=6,
         equalizer=f=100:t=o:w=1:g=4,
         equalizer=f=250:t=o:w=1:g=2,
         equalizer=f=700:t=o:w=1.5:g=-1,
         equalizer=f=3000:t=o:w=2:g=1,
         equalizer=f=8000:t=o:w=2:g=2,
         equalizer=f=14000:t=o:w=3:g=3[beat_eq];
    [beat_eq]acompressor=threshold=-22dB:ratio=3:attack=15:release=200:makeup=3[tape_comp];
    [tape_comp]aeval='#{TRIODE_PENTODE}'[hedd];
    [hedd]aecho=0.5:0.3:25|50:0.1|0.05[spring];
    [spring]volume=0.82[beat_out]
  FILT
  "-map", "[beat_out]", "-ar", "44100", BEAT_PRE

# Vocals: crystal clarity — wide stereo doubling, massive air shelf, HEDD on vocals too
run "Vocals: crystal + HEDD + wide stereo double",
  "ffmpeg", "-y", "-i", VOCALS,
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=160:t=o:w=1:g=-10,
          equalizer=f=350:t=o:w=1:g=-4,
          equalizer=f=1000:t=o:w=1.5:g=2,
          equalizer=f=2500:t=o:w=2:g=6,
          equalizer=f=5000:t=o:w=2:g=5,
          equalizer=f=10000:t=o:w=3:g=6,
          equalizer=f=16000:t=o:w=3:g=5[voc_eq];
    [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=6:release=100:makeup=5[voc_comp];
    [voc_comp]aeval='#{TRIODE_PENTODE}'[voc_hedd];
    [voc_hedd]asplit=3[va][vb][vc];
    [va]volume=1.0[vdry];
    [vb]adelay=#{DOTTED_8TH}|#{DOTTED_8TH},
        aecho=0.65:0.55:400|800:0.35|0.15[vplate];
    [vc]chorus=0.5:0.9:18|22:0.08|0.06:0.2|0.25:1.0|1.0[vdouble];
    [vdry][vplate][vdouble]amix=inputs=3:weights=1.4 0.45 0.35[voc_out]
  FILT
  "-map", "[voc_out]", "-ar", "44100", VOCALS_PRE

# C minor pad: C(261.63) Eb(311.13) G(392.00) low-C(130.81)
# Warmer/more soulful than Db minor in v9
run "Pad: C minor chord — warm soulful",
  "ffmpeg", "-y",
  "-f", "lavfi",
  "-i", "aevalsrc=0.14*sin(2*PI*130.81*t)+0.11*sin(2*PI*261.63*t)+0.09*sin(2*PI*311.13*t)+0.10*sin(2*PI*392.00*t)+0.06*sin(2*PI*523.25*t):s=44100:c=stereo:d=146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=1000:t=o:w=2:g=-5,
         equalizer=f=4000:t=o:w=2:g=-10,
         equalizer=f=100:t=o:w=1:g=3[pad_eq];
    [pad_eq]aecho=0.85:0.8:500|1000:0.4|0.2[pad_echo];
    [pad_echo]chorus=0.5:0.8:35|45:0.25|0.2:0.35|0.25:1.2|1.6[pad_chorus];
    [pad_chorus]volume=0.18[pad_out]
  FILT
  "-map", "[pad_out]", "-ar", "44100", PAD

# Subtle crackle
run "Crackle: light vinyl texture",
  "ffmpeg", "-y",
  "-f", "lavfi", "-i", "anoisesrc=r=44100:color=pink:amplitude=0.015:d=146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=4500:t=o:w=3:g=5,
         equalizer=f=80:t=o:w=1:g=-18,
         volume=0.10[crack_out]
  FILT
  "-map", "[crack_out]", "-ar", "44100", CRACKLE

# Master: HEDD on the bus, vintage tape feel, warm limit
# Phoenix II style: harmonic enhancement + gentle limiting
run "Master: HEDD bus + vintage tape + warm limit",
  "ffmpeg", "-y",
  "-i", BEAT_PRE, "-i", VOCALS_PRE, "-i", PAD, "-i", CRACKLE,
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]volume=0.84[b];
    [1:a]volume=1.22[v];
    [2:a]volume=0.20[p];
    [3:a]volume=0.12[c];
    [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.22 0.20 0.12[mix];
    [mix]acompressor=threshold=-24dB:ratio=2:attack=20:release=300:makeup=2[glue];
    [glue]aeval='#{TRIODE_PENTODE}'[bus_hedd];
    [bus_hedd]equalizer=f=45:t=o:w=0.7:g=3,
               equalizer=f=150:t=o:w=1:g=2,
               equalizer=f=700:t=o:w=1.5:g=-1,
               equalizer=f=12000:t=o:w=2:g=2[master_eq];
    [master_eq]aeval='tanh(val(0)*2.2)/tanh(2.2)|tanh(val(1)*2.2)/tanh(2.2)'[tape_sat];
    [tape_sat]aecho=0.2:0.15:15:0.05[air];
    [air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=4:release=40:level=disabled[out]
  FILT
  "-map", "[out]", "-b:a", "320k", OUT

puts "\n✓ Mix v10 done → #{OUT}"
