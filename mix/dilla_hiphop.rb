#!/usr/bin/env ruby
# frozen_string_literal: true
#
# J Dilla — MPC-style hip-hop beat synthesized from primitives.
# 86 BPM × 8 bars. Off-grid kicks, snare drag, hat swing, vinyl crackle.
#
# Usage:  ruby dilla_hiphop.rb [out.mp3]   default: ./dilla_hiphop.mp3

DIR = __dir__
BPM  = 86
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
  beat = 60.0 / BPM
  bar  = beat * 4
  step = beat / 4

  kick_steps  = [0, 7, 10, 14]
  snare_steps = [4, 12]
  hat_steps   = [0, 2, 4, 6, 8, 10, 12, 14]
  open_steps  = [6]

  kicks  = kick_steps.map  { |s| (s * step).round(4) }
  snares = snare_steps.map { |s| (s * step + 0.018).round(4) }
  hats   = hat_steps.each_with_index.map { |s, i| (s * step + (i.odd? ? 0.012 : 0)).round(4) }
  opens  = open_steps.map  { |s| (s * step).round(4) }

  kick_sig = kicks.map  { |t| "between(t,#{t},#{t + 0.25})*0.9*exp(-(t-#{t})*6)*sin(2*PI*(100*(t-#{t})-150*(t-#{t})*(t-#{t})))" }.join("+")
  sub_sig  = kicks.map  { |t| "between(t,#{t},#{t + 0.45})*0.4*exp(-(t-#{t})*3.5)*sin(2*PI*32.70*(t-#{t}))" }.join("+")
  snr_env  = snares.map { |t| "between(t,#{t},#{t + 0.12})*exp(-(t-#{t})*20)" }.join("+")
  hat_env  = hats.map   { |t| "between(t,#{t},#{t + 0.05})*exp(-(t-#{t})*60)" }.join("+")
  opn_env  = opens.map  { |t| "between(t,#{t},#{t + 0.2})*exp(-(t-#{t})*12)" }.join("+")

  bar_dur = bar.round(3)
  total   = (bar_dur * BARS).round(2)
  bar_smp = (bar_dur * 44_100).to_i
  loops   = BARS - 1

  inputs = [
    *lavfi("aevalsrc='#{kick_sig}':d=#{bar_dur}:s=44100"),
    *lavfi("aevalsrc='#{sub_sig}':d=#{bar_dur}:s=44100"),
    *lavfi("anoisesrc=color=white:r=44100:amplitude=0.5:d=#{bar_dur}"),
    *lavfi("anoisesrc=color=pink:r=44100:amplitude=0.04:d=#{total}"),
  ]

  filt = <<~F
    [0:a]aformat=channel_layouts=stereo,equalizer=f=60:t=o:w=1:g=3,
         acompressor=threshold=-12dB:ratio=4:attack=1:release=60:makeup=2,
         aloop=loop=#{loops}:size=#{bar_smp},asetpts=N/SR/TB[kick];
    [1:a]aformat=channel_layouts=stereo,lowpass=f=120,equalizer=f=40:t=o:w=0.8:g=4,
         aloop=loop=#{loops}:size=#{bar_smp},asetpts=N/SR/TB[sub];
    [2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no];
    [ns]volume='(#{snr_env})*0.7':eval=frame,equalizer=f=200:t=o:w=2:g=3,bandpass=f=300:w=400,
        aloop=loop=#{loops}:size=#{bar_smp},asetpts=N/SR/TB[snare];
    [nh]volume='(#{hat_env})*0.3':eval=frame,highpass=f=6000,
        aloop=loop=#{loops}:size=#{bar_smp},asetpts=N/SR/TB[hat];
    [no]volume='(#{opn_env})*0.25':eval=frame,bandpass=f=5500:w=5000,
        aloop=loop=#{loops}:size=#{bar_smp},asetpts=N/SR/TB[open];
    [kick][sub][snare][hat][open]amix=inputs=5:weights=1.3 0.85 0.9 0.55 0.5:duration=longest[drums];
    [drums]acompressor=threshold=-16dB:ratio=4:attack=2:release=80:makeup=3[drums_comp];
    [drums_comp]aeval='tanh(val(0)*1.6)/tanh(1.6)|tanh(val(1)*1.6)/tanh(1.6)'[drums_sat];
    [drums_sat]lowpass=f=11000,equalizer=f=200:t=o:w=2:g=-2,equalizer=f=2500:t=o:w=2:g=-3[lofi];
    [3:a]equalizer=f=4500:t=o:w=3:g=5,equalizer=f=80:t=o:w=1:g=-18,volume=0.15[crackle];
    [lofi][crackle]amix=inputs=2:weights=1 0.4:duration=first[mixed];
    [mixed]alimiter=level_in=1.0:level_out=0.97:limit=0.92:attack=4:release=40[out]
  F

  render "dilla beat (#{BPM} BPM × #{BARS} bars → #{total}s)", dest,
    inputs: inputs, map: "[out]", filter: filt
end

dest = ARGV[0] || File.join(DIR, "dilla_hiphop.mp3")
synthesize(dest)
puts "done -> #{dest}"
