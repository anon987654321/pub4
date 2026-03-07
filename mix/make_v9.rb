#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Mix v9 — "Afta-1 Psychedelic Space" — maximal, immersive, outer space
# Beat pitched down 4 semitones, slowed 8%, cathedral vocal reverb,
# shimmer chorus, phaser, bitcrusher, generated sine pad in Db minor,
# everything simultaneously — underwater, dream logic.

BEAT   = "/sdcard/Download/Voicemails.mp3"
VOCALS = "/root/pub4/mix/vocals_precise.wav"
OUT    = "/root/pub4/mix/final_mix_v9.mp3"

BPM        = 118.6
SLOW_RATIO = 0.92   # slowed 8%
NEW_BPM    = BPM * SLOW_RATIO  # ~109.1 BPM
BEAT_MS    = (60_000 / NEW_BPM).to_i
DOTTED_8TH = (BEAT_MS * 0.75).to_i
HALF       = (BEAT_MS * 2).to_i

BEAT_PRE   = "/tmp/v9_beat.wav"
VOCALS_PRE = "/tmp/v9_vocals.wav"
PAD        = "/tmp/v9_pad.wav"
CRACKLE    = "/tmp/v9_crackle.wav"

def run(label, *cmd)
  puts "\n>>> #{label}"
  success = system(*cmd.flatten.map(&:to_s))
  abort "FAILED: #{label}" unless success
  puts "    OK"
end

# Beat: slow down 8% + pitch down 4 semitones (asetrate trick)
# asetrate changes pitch without tempo, then atempo corrects tempo
# net result: pitch -4 semitones at original tempo... then we slow tempo
# pitch -4 semitones = factor 0.7937 on sample rate
run "Beat: pitched down 4st + slowed + psychedelic",
  "ffmpeg", "-y",
  "-stream_loop", "-1", "-i", BEAT,
  "-t", "146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]asetrate=44100*0.7937,aresample=44100,atempo=#{SLOW_RATIO}[pitched];
    [pitched]equalizer=f=50:t=o:w=0.7:g=9,
             equalizer=f=100:t=o:w=1:g=5,
             equalizer=f=600:t=o:w=2:g=-3,
             equalizer=f=3000:t=o:w=2:g=-5[beat_eq];
    [beat_eq]aphaser=in_gain=0.6:out_gain=0.8:delay=4:decay=0.5:speed=0.4:type=triangular[beat_phase];
    [beat_phase]aecho=0.7:0.5:200|400:0.3|0.15[beat_echo];
    [beat_echo]acompressor=threshold=-16dB:ratio=5:attack=4:release=80:makeup=3[beat_comp];
    [beat_comp]volume=0.78[beat_out]
  FILT
  "-map", "[beat_out]", "-ar", "44100", BEAT_PRE

# Vocals: cathedral reverb 8s decay, triple shimmer chorus, bitcrushed highs, phaser
run "Vocals: cathedral + shimmer + bitcrush + phaser",
  "ffmpeg", "-y", "-i", VOCALS,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
    [vd]adelay=#{DOTTED_8TH}|#{HALF},
        acrusher=level_in=1.8:level_out=0.5:bits=6:mode=log:aa=1[voc_bit];
    [voc_dry][voc_cathedral][voc_shimmer][voc_bit]amix=inputs=4:weights=1 0.7 0.5 0.2[voc_wet];
    [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=3:decay=0.4:speed=0.2:type=sinusoidal[voc_phase];
    [voc_phase]flanger=delay=6:depth=5:speed=0.2:shape=sinusoidal[voc_flange];
    [voc_flange]volume=1.3[voc_out]
  FILT
  "-map", "[voc_out]", "-ar", "44100", VOCALS_PRE

# Synth pad — Db minor chord: Db(277.18Hz) + F(349.23Hz) + Ab(415.30Hz) + low Db(138.59Hz)
# Long attack swell, filtered to be warm/dark, 146s duration
run "Pad: Db minor sine chord swell",
  "ffmpeg", "-y",
  "-f", "lavfi",
  "-i", "aevalsrc=0.12*sin(2*PI*138.59*t)+0.10*sin(2*PI*277.18*t)+0.08*sin(2*PI*349.23*t)+0.09*sin(2*PI*415.30*t)+0.05*sin(2*PI*554.37*t):s=44100:c=stereo:d=146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=800:t=o:w=2:g=-6,
         equalizer=f=3000:t=o:w=2:g=-10,
         aecho=0.9:0.85:600|1200:0.5|0.3[pad_echo];
    [pad_echo]chorus=0.6:0.8:40|50:0.3|0.25:0.4|0.3:1.5|2.0[pad_chorus];
    [pad_chorus]aphaser=in_gain=0.6:out_gain=0.8:delay=5:decay=0.6:speed=0.15:type=sinusoidal[pad_phase];
    [pad_phase]volume=0.22[pad_out]
  FILT
  "-map", "[pad_out]", "-ar", "44100", PAD

# Subtle crackle under everything
run "Crackle: distant vinyl",
  "ffmpeg", "-y",
  "-f", "lavfi", "-i", "anoisesrc=r=44100:color=pink:amplitude=0.02:d=146",
  "-filter_complex", <<~FILT.tr("\n", " "),
    [0:a]equalizer=f=5000:t=o:w=3:g=6,
         equalizer=f=80:t=o:w=1:g=-18,
         volume=0.12[crack_out]
  FILT
  "-map", "[crack_out]", "-ar", "44100", CRACKLE

# Master: full psychedelic chain — 3-band comp + tape sat + space echo + hard limit
run "Master: psychedelic space chain",
  "ffmpeg", "-y",
  "-i", BEAT_PRE, "-i", VOCALS_PRE, "-i", PAD, "-i", CRACKLE,
  "-filter_complex", <<~FILT.tr("\n", " "),
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
  FILT
  "-map", "[out]", "-b:a", "320k", OUT

puts "\n✓ Mix v9 done → #{OUT}"
