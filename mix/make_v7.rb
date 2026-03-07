#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Mix v7 — J Dilla x Flying Lotus x Afta-1 inspired
# Heavy effects, heavy master chain, vinyl crackle layer.
# Requires only: ffmpeg

BEAT   = "/sdcard/Download/Voicemails.mp3"
VOCALS = "/root/pub4/mix/vocals_processed.wav"
OUT    = "/root/pub4/mix/final_mix_v7.mp3"

BPM        = 118.6
BEAT_MS    = (60_000 / BPM).to_i   # ~506ms quarter note
DOTTED_8TH = (BEAT_MS * 0.75).to_i # ~379ms

BEAT_PRE   = "/tmp/v7_beat.wav"
VOCALS_PRE = "/tmp/v7_vocals.wav"
CRACKLE    = "/tmp/v7_crackle.wav"

def run(label, *cmd)
  puts "\n>>> #{label}"
  flat = cmd.flatten.map(&:to_s)
  success = system(*flat)
  abort "FAILED: #{label}" unless success
  puts "    OK"
end

# ─── 1. Beat: M/S split, sub boost, crunch, room echo ─────────────────────────
run "Beat: M/S + EQ + crunch + room",
  "ffmpeg", "-y", "-i", BEAT,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[beat_out]", "-ar", "44100", BEAT_PRE

# ─── 2. Vocals: clearer, shinier, more precise pitch ─────────────────────────
# - Mud cut at 180-300Hz, presence lift 2.5-5kHz, air at 10k+16k
# - Tight compression (low ratio, fast attack) to keep clarity
# - Less reverb decay so words cut through
# - Pitch-precise chorus: narrow detune (+/-5 cents) = shimmery not washy
# - Plate reverb as parallel send only (dry stays up front)
# - Ping-pong delay with high-pass filter so tail doesn't muddy
run "Vocals: clear + shiny + precise",
  "ffmpeg", "-y", "-i", VOCALS,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
    [vc]adelay=#{DOTTED_8TH}|#{DOTTED_8TH * 2},
        equalizer=f=400:t=h:w=1:g=0[voc_ping];
    [vd]chorus=0.5:0.9:20|25:0.1|0.08:0.15|0.2:1.0|1.0[voc_shimmer];
    [voc_dry][voc_plate][voc_ping][voc_shimmer]amix=inputs=4:weights=1.4 0.4 0.35 0.5[voc_wet];
    [voc_wet]volume=1.35[voc_out]
  FILT
  "-map", "[voc_out]", "-ar", "44100", VOCALS_PRE

# ─── 3. Vinyl crackle layer ────────────────────────────────────────────────────
run "Crackle: vinyl surface noise",
  "ffmpeg", "-y",
  "-f", "lavfi",
  "-i", "anoisesrc=r=44100:color=pink:amplitude=0.025:d=300",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=3000:t=o:w=3:g=5,
         equalizer=f=80:t=o:w=1:g=-15,
         volume=0.18[crack_out]
  FILT
  "-map", "[crack_out]", "-ar", "44100", CRACKLE

# ─── 4. Final mix + master chain ──────────────────────────────────────────────
# Multiband-style triple compression, tape saturation (tanh), air echo, hard limit
run "Master chain: mix + compress + tape sat + limit",
  "ffmpeg", "-y",
  "-i", BEAT_PRE,
  "-i", VOCALS_PRE,
  "-i", CRACKLE,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[out]",
  "-b:a", "320k",
  OUT

puts "\n✓ Mix v7 done → #{OUT}"
