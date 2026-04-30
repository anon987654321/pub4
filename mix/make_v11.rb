#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Mix v11 — "Clean & Soothing"
# - 2kHz pluck notched out with dynamic EQ
# - Vocals at ORIGINAL pitch (tempo-matched only, no pitch shift)
# - Low-pass smoothing on beat highs
# - M/S stem separation (mid = bass/kick, side = pads/hats)
# - Phase summing: mono-sum bass frequencies for punch
# - Slow phaser + warm chorus modulation throughout
# - J Dilla: micro-timing feel via tremolo wobble on side channel

BEAT   = "/sdcard/Download/Voicemails.mp3"
VOCALS = File.expand_path("~/pub4/mix/vocals_original_pitch.wav")  # original pitch, tempo-matched
OUT    = "/root/pub4/mix/final_mix_v11.mp3"

BPM        = 118.6
BEAT_MS    = (60_000 / BPM).to_i
DOTTED_8TH = (BEAT_MS * 0.75).to_i
EIGHTH     = (BEAT_MS * 0.5).to_i

BEAT_PRE   = "/tmp/v11_beat.wav"
VOCALS_PRE = "/tmp/v11_vocals.wav"
CRACKLE    = "/tmp/v11_crackle.wav"

def run(label, *cmd)
  puts "\n>>> #{label}"
  success = system(*cmd.flatten.map(&:to_s))
  abort "FAILED: #{label}" unless success
  puts "    OK"
end

# Beat: M/S split, notch 2kHz pluck, low-pass smooth highs, phase-sum bass
# Mid channel: bass + kick only (low-pass 300Hz) → mono summed for punch
# Side channel: everything else, with Dilla wobble tremolo + phaser
run "Beat: pluck notch + M/S + low-pass + phase sum",
  "ffmpeg", "-y",
  "-stream_loop", "-1", "-i", BEAT,
  "-t", "146",
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[beat_out]", "-ar", "44100", BEAT_PRE

# Vocals: original pitch, clear, warm low-pass above 12kHz to soften
run "Vocals: original pitch + warm + soothing",
  "ffmpeg", "-y", "-i", VOCALS,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
    [vc]adelay=#{DOTTED_8TH}|#{DOTTED_8TH * 2},
        chorus=0.5:0.8:20|25:0.08|0.06:0.2|0.25:1.0|1.0[vshine];
    [vdry][vplate][vshine]amix=inputs=3:weights=1.3 0.4 0.3[voc_wet];
    [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=2:decay=0.3:speed=0.25:type=sinusoidal[voc_phase];
    [voc_phase]volume=1.3[voc_out]
  FILT
  "-map", "[voc_out]", "-ar", "44100", VOCALS_PRE

# Light crackle
run "Crackle: soft vinyl",
  "ffmpeg", "-y",
  "-f", "lavfi", "-i", "anoisesrc=r=44100:color=pink:amplitude=0.012:d=146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=5000:t=o:w=3:g=4,
         equalizer=f=80:t=o:w=1:g=-18,
         volume=0.10[crack_out]
  FILT
  "-map", "[crack_out]", "-ar", "44100", CRACKLE

# Master: gentle glue, warm tape, soothing low-pass, soft limit
run "Master: warm + smooth + soothing",
  "ffmpeg", "-y",
  "-i", BEAT_PRE, "-i", VOCALS_PRE, "-i", CRACKLE,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[out]", "-b:a", "320k", OUT

puts "\n✓ Mix v11 done → #{OUT}"
