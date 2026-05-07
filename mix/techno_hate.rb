#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Hate techno — hard, dark, distorted. 142 BPM × 8 bars.
# 4-on-the-floor saturated kick, acid-bass C-minor progression (i-iv-v),
# industrial closed hats on offbeats, layered claps, hard limit.
#
# Usage:  ruby techno_hate.rb [out.mp3]   default: ./techno_hate.mp3

DIR  = __dir__
BPM  = 142
BARS = 8

def run(label, *cmd)
  puts ">>> #{label}"
  abort "fail: #{label}" unless system(*cmd.flatten.map(&:to_s))
end

def render(label, dest, inputs:, filter:, map:, args: ["-b:a", "320k"])
  run label, "ffmpeg", "-y", *inputs,
      "-filter_complex", filter.tr("\n", " "),
      "-map", map, *args, dest
end

def lavfi(src) = ["-f", "lavfi", "-i", src]

def synthesize(dest)
  beat  = 60.0 / BPM
  bar   = beat * 4
  step  = beat / 4
  total = (bar * BARS).round(3)

  kick_steps = [0, 4, 8, 12]      # quarter pulse
  clap_steps = [4, 12]            # 2 and 4
  hat_steps  = [2, 6, 10, 14]     # offbeat 8ths
  open_steps = [14]                # tail-into-bar
  acid_steps = [0, 3, 6, 8, 11, 14]

  bass_notes = [65.41, 65.41, 87.31, 65.41, 98.00, 98.00, 87.31, 65.41]  # C C F C G G F C

  kicks = BARS.times.flat_map { |b| kick_steps.map { |s| (b * bar + s * step).round(4) } }
  claps = BARS.times.flat_map { |b| clap_steps.map { |s| (b * bar + s * step).round(4) } }
  hats  = BARS.times.flat_map { |b| hat_steps.map  { |s| (b * bar + s * step).round(4) } }
  opens = BARS.times.flat_map { |b| open_steps.map { |s| (b * bar + s * step).round(4) } }

  acid_hits = BARS.times.flat_map do |b|
    f = bass_notes[b]
    acid_steps.map { |s| [(b * bar + s * step).round(4), f] }
  end

  kick_sig = kicks.map { |t| "between(t,#{t},#{t + 0.18})*0.95*exp(-(t-#{t})*8)*sin(2*PI*(110*(t-#{t})-250*(t-#{t})*(t-#{t})))" }.join("+")
  acid_sig = acid_hits.map { |(t, f)| "between(t,#{t},#{t + 0.14})*0.6*exp(-(t-#{t})*9)*sin(2*PI*#{f}*(t-#{t}))" }.join("+")

  clap_env = claps.flat_map { |t|
    t1 = (t + 0.012).round(4)
    t2 = (t + 0.024).round(4)
    [
      "between(t,#{t},#{t + 0.04})*exp(-(t-#{t})*40)",
      "between(t,#{t1},#{(t1 + 0.04).round(4)})*exp(-(t-#{t1})*50)",
      "between(t,#{t2},#{(t2 + 0.05).round(4)})*exp(-(t-#{t2})*30)",
    ]
  }.join("+")

  hat_env = hats.map  { |t| "between(t,#{t},#{t + 0.04})*exp(-(t-#{t})*70)" }.join("+")
  opn_env = opens.map { |t| "between(t,#{t},#{t + 0.5})*exp(-(t-#{t})*10)" }.join("+")

  inputs = [
    *lavfi("aevalsrc='#{kick_sig}':d=#{total}:s=44100"),
    *lavfi("aevalsrc='#{acid_sig}':d=#{total}:s=44100"),
    *lavfi("anoisesrc=color=white:r=44100:amplitude=0.5:d=#{total}"),
  ]

  filt = <<~F
    [0:a]aformat=channel_layouts=stereo,equalizer=f=55:t=o:w=0.7:g=4,
         aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)',
         acompressor=threshold=-10dB:ratio=6:attack=1:release=40:makeup=3[kick];
    [1:a]aformat=channel_layouts=stereo,
         aeval='tanh(val(0)*3.5)/tanh(3.5)|tanh(val(1)*3.5)/tanh(3.5)',
         equalizer=f=300:t=o:w=2:g=3,equalizer=f=1500:t=o:w=2:g=4,
         lowpass=f=4000[acid];
    [2:a]aformat=channel_layouts=stereo,asplit=3[nc][nh][no];
    [nc]volume='(#{clap_env})*0.6':eval=frame,bandpass=f=1500:w=2000,
        aecho=0.5:0.4:30|60:0.2|0.1[clap];
    [nh]volume='(#{hat_env})*0.4':eval=frame,highpass=f=8000[hat];
    [no]volume='(#{opn_env})*0.3':eval=frame,bandpass=f=7000:w=5000[open];
    [kick][acid][clap][hat][open]amix=inputs=5:weights=1.4 1.0 0.7 0.5 0.4:duration=longest[drums];
    [drums]highpass=f=30,acompressor=threshold=-14dB:ratio=8:attack=1:release=50:makeup=4[drums_comp];
    [drums_comp]aeval='tanh(val(0)*2.0)/tanh(2.0)|tanh(val(1)*2.0)/tanh(2.0)'[drums_sat];
    [drums_sat]equalizer=f=80:t=o:w=0.8:g=2,equalizer=f=8000:t=o:w=2:g=3[master_eq];
    [master_eq]alimiter=level_in=1.0:level_out=0.99:limit=0.95:attack=2:release=20[out]
  F

  render "techno hate (#{BPM} BPM × #{BARS} bars → #{total}s)", dest,
    inputs: inputs, map: "[out]", filter: filt
end

dest = ARGV[0] || File.join(DIR, "techno_hate.mp3")
synthesize(dest)
puts "done -> #{dest}"
