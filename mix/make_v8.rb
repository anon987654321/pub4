#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Mix v8 — "Dilla Drunk" — raw, sparse, deconstructed
# Sub-bass forward, vocals nearly dry, heavy vinyl crackle in gaps,
# drunk micro-timing via pitch wobble, breathes and clips naturally.

BEAT   = "/sdcard/Download/Voicemails.mp3"
VOCALS = "/root/pub4/mix/vocals_precise.wav"
OUT    = "/root/pub4/mix/final_mix_v8.mp3"

BPM        = 118.6
VOC_DUR    = 146.0  # loop beat to match vocal = beat length (beat is longer, use full beat)
BEAT_MS    = (60_000 / BPM).to_i
EIGHTH     = (BEAT_MS * 0.5).to_i

BEAT_PRE   = "/tmp/v8_beat.wav"
VOCALS_PRE = "/tmp/v8_vocals.wav"
CRACKLE    = "/tmp/v8_crackle.wav"

def run(label, *cmd)
  puts "\n>>> #{label}"
  success = system(*cmd.flatten.map(&:to_s))
  abort "FAILED: #{label}" unless success
  puts "    OK"
end

# Beat: sub-bass heavy, strip mids, drunk wobble via slow tremolo/pitch mod
# Loop beat to fill full duration
run "Beat: sub focus + drunk wobble",
  "ffmpeg", "-y",
  "-stream_loop", "-1", "-i", BEAT,
  "-t", "146",
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[beat_out]", "-ar", "44100", BEAT_PRE

# Vocals: nearly dry — tiny room only, tight comp, no reverb tail
run "Vocals: dry + tight + present",
  "ffmpeg", "-y", "-i", VOCALS,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[voc_out]", "-ar", "44100", VOCALS_PRE

# Heavy vinyl crackle — prominent, sits in the gaps
run "Crackle: heavy vinyl",
  "ffmpeg", "-y",
  "-f", "lavfi", "-i", "anoisesrc=r=44100:color=pink:amplitude=0.05:d=146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=4000:t=o:w=3:g=8,
         equalizer=f=80:t=o:w=1:g=-20,
         volume=0.3[crack_out]
  FILT
  "-map", "[crack_out]", "-ar", "44100", CRACKLE

# Master: tape sat only, no comp, soft limit — let it breathe
run "Master: tape sat + breathe",
  "ffmpeg", "-y",
  "-i", BEAT_PRE, "-i", VOCALS_PRE, "-i", CRACKLE,
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]volume=0.85[b];
    [1:a]volume=1.4[v];
    [2:a]volume=0.35[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.4 0.35[mix];
    [mix]equalizer=f=60:t=o:w=0.8:g=3,
         equalizer=f=5000:t=o:w=2:g=2[master_eq];
    [master_eq]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[tape];
    [tape]alimiter=level_in=1.0:level_out=0.97:limit=0.94:attack=5:release=80:level=disabled[out]
  FILT
  "-map", "[out]", "-b:a", "320k", OUT

puts "\n✓ Mix v8 done → #{OUT}"
