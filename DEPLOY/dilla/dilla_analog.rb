#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true
# dilla_analog.rb
# Full analog-pad restoration renderer for Dilla/Madlib/FlyLo-inspired music.
# Original synthesis only: no copyrighted sample downloading.
#
# Usage:
#   ruby dilla/dilla_analog.rb render dilla/analog_full.mp3
#   ruby dilla/dilla_analog.rb liveset dilla/analog_liveset.mp3 12
#   ruby dilla/dilla_analog.rb chords
#   ruby dilla/dilla_analog.rb clean input.wav output.wav
#   ruby dilla/dilla_analog.rb stems dilla/samples/demucs dilla/samples/manifest.json

require "json"
require "fileutils"

DIR = File.expand_path(__dir__)
BPM = (ENV["BPM"] || 86).to_f
BARS = (ENV["BARS"] || 96).to_i
SR = 44_100

# 13 restored Dilla-ish progressions: dark 9ths, maj9s, suspended clusters, altered color.
PAD_CHORDS = [
  { name: "Fm9",      hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj9",   hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Cm9",      hz: [130.81, 155.56, 196.00, 233.08, 293.66] },
  { name: "Ebmaj9",   hz: [155.56, 196.00, 233.08, 293.66, 349.23] },
  { name: "Abmaj9",   hz: [207.65, 261.63, 311.13, 392.00, 466.16] },
  { name: "Dm9",      hz: [146.83, 174.61, 220.00, 261.63, 329.63] },
  { name: "Gm9",      hz: [196.00, 233.08, 293.66, 349.23, 440.00] },
  { name: "Bm7b5+9",  hz: [123.47, 146.83, 174.61, 220.00, 261.63] },
  { name: "E altered",hz: [164.81, 196.00, 233.08, 293.66, 349.23] },
  { name: "Am9",      hz: [110.00, 130.81, 164.81, 196.00, 246.94] },
  { name: "Bbm9",     hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Gbmaj9",   hz: [92.50, 116.54, 138.59, 174.61, 207.65] },
  { name: "C cluster", hz: [130.81, 138.59, 196.00, 233.08, 311.13] }
].freeze

ROOTS = [43.65, 49.00, 51.91, 38.89, 46.25].freeze
PRIMES = [97, 109, 127, 149, 167, 191, 223, 251].freeze

# Analog authenticity controls.
ANALOG = {
  osc_layers: 5,
  drift_cents: 7.0,
  bad_tune_spike_cents: 16.0,
  lowpass_hz: 2600,
  sp_bits: 12,
  sp_ratio: 44_100.0 / 26_040.0,
  tape_dc: 0.05,
  chorus_delay_l_ms: 9,
  chorus_delay_r_ms: 13,
  vinyl_level: 0.14,
  pad_sidechain_hint: 0.72
}.freeze

def sh!(*cmd)
  puts ">>> #{cmd.flatten.join(' ')}"
  abort "failed" unless system(*cmd.flatten.map(&:to_s))
end

def lavfi(src) = ["-f", "lavfi", "-i", src]
def expr(parts) = parts.empty? ? "0" : parts.join("+")

def section_for_bar(b, total)
  return [:intro, 0.42] if b < 8
  return [:a, 1.00] if b < 24
  return [:a2, 1.00] if b < 40
  return [:break, 0.55] if b < 48
  return [:b, 1.00] if b < 64
  return [:drop, 0.72] if b < 72
  return [:c, 1.00] if b < 88
  [:outro, [0.25, 1.0 - ((b - 88) / [12.0, total - 88.0].max)].max]
end

def rotate_chord(chord, bars)
  hz = chord[:hz].rotate((bars / 8) % chord[:hz].length)
  # Probabilistic tension note restoration: b9/#11/13-like color via ratio offsets.
  extra = case bars % 12
          when 0 then hz[0] * 1.067
          when 4 then hz[2] * 1.414
          when 8 then hz[3] * 1.122
          else nil
          end
  extra ? (hz + [extra]) : hz
end

def schedule(bars)
  beat = 60.0 / BPM
  bar = beat * 4
  step = bar / 16
  events = Hash.new { |h, k| h[k] = [] }
  kick_patterns = [[0,7,10,14], [0,5,7,10,14], [0,3,7,10,12,14], [0,6,9,14]]

  bars.times do |b|
    sec, den = section_for_bar(b, bars)
    base = b * bar
    kp = kick_patterns[(b / 8 + b % 3) % kick_patterns.length].dup
    kp = [0,3,6,7,10,12,14,15] if b % 16 == 15
    kp = [0,10] if sec == :intro && b > 2
    kp = [] if sec == :intro && b <= 2
    kp = (b.even? ? [0] : [0,7]) if sec == :break
    kp = (b.even? ? [0,10] : [0,7,14]) if sec == :drop
    kp = [0] if sec == :outro && b > bars - 8 && b % 4 == 0

    kp.each_with_index do |s, i|
      # Separate timing grids: late/straight kicks, early/variable snares, late hats, laggy bass.
      t = base + s * step + [0.000, 0.006, 0.011, -0.004, 0.018][(b + i) % 5]
      events[:kick] << [t, den]
      events[:bass] << [t + 0.023, den, ROOTS[(b / 4 + i) % ROOTS.length]] unless sec == :intro
    end

    [4, 12].each do |s|
      events[:snare] << [base + s * step + [-0.010, -0.006, 0.004, 0.010, 0.017][b % 5], den] unless sec == :intro
    end

    (b.even? ? [6,11] : [3,6,11,15]).each do |s|
      events[:ghost] << [base + s * step + [-0.014, 0.006, 0.018][(b + s) % 3], den * 0.32] unless [:intro, :drop].include?(sec)
    end

    hats = b % 16 == 7 ? [0,4,8,12] : [0,2,4,6,8,10,12,14]
    hats = b.even? ? [] : [0,4,8,12] if sec == :break
    hats.each_with_index do |s, i|
      jitter = [-0.004, 0.000, 0.003, 0.006][(b + s) % 4]
      events[:hat] << [base + s * step + (i.odd? ? 0.018 : 0.002) + jitter, den * 0.52]
    end

    events[:open] << [base + 6 * step + 0.008, den * 0.30] if ![:intro, :break].include?(sec) && [1,3].include?(b % 4)

    if b >= 2 && b % 4 == 0
      chord = rotate_chord(PAD_CHORDS[(b / 4) % PAD_CHORDS.length], b)
      sustain = 3.2 + (b % 3) * 0.9
      events[:pad] << [base + 0.03, den, chord, sustain]
    end

    if b >= 2 && b % 2 == 0
      chord = rotate_chord(PAD_CHORDS[(b / 4 + 3) % PAD_CHORDS.length], b)
      events[:chop] << [base + [1,2,5,9,13][b % 5] * step + [-0.022, 0.0, 0.017][b % 3], den, chord]
    end

    events[:riser] << [base + 2 * beat, 0.13] if [7,23,39,47,63,71,87].include?(b)
    events[:stop] << [base + 3 * beat, 0.18] if [23,39,47,63,71,87].include?(b)
  end
  events
end

def pad_expression(t, v, chord, sustain, bar_index)
  parts = chord.each_with_index.map do |f, i|
    # Five-layer analog voice: saw-ish fundamental, detuned saw, triangle-ish partial, sine, quiet square-ish odd partial.
    drift = 1.0 + ((i - 2) * 0.0017) + (Math.sin((bar_index + i) * 1.7) * 0.0009)
    spike = (bar_index % 11 == i ? (ANALOG[:bad_tune_spike_cents] / 1200.0) : 0.0)
    ff = f * drift * (2.0 ** spike)
    [
      "sin(2*PI*#{ff}*(t-#{t}))",
      "0.55*sin(2*PI*#{ff * 1.004}*(t-#{t}))",
      "0.32*sin(2*PI*#{ff * 2.005}*(t-#{t}))",
      "0.20*sin(2*PI*#{ff * 0.5}*(t-#{t}))",
      "0.11*sin(2*PI*#{ff * 3.0}*(t-#{t}))"
    ].join("+")
  end.join("+")
  # Slow envelope, breathing tremolo, capacitor-like lag by filtering in ffmpeg later.
  "between(t,#{t},#{t+sustain})*#{v}*0.035*exp(-(t-#{t})*0.26)*(0.78+0.22*sin(2*PI*0.23*(t-#{t})))*(#{parts})"
end

def render(dest, bars: BARS)
  beat = 60.0 / BPM
  dur = (bars * beat * 4).round(3)
  ev = schedule(bars)

  kick = ev[:kick].map { |t, v| "between(t,#{t},#{t+0.42})*#{v}*0.95*exp(-(t-#{t})*7.4)*sin(2*PI*(45+115*exp(-20*(t-#{t})))*(t-#{t}))" }
  bass = ev[:bass].map { |t, v, f| "between(t,#{t},#{t+0.46})*#{v}*0.42*exp(-(t-#{t})*3.2)*sin(2*PI*#{f}*(t-#{t}))" }
  snare = ev[:snare].map { |t, v| "between(t,#{t},#{t+0.18})*#{v}*0.60*exp(-(t-#{t})*23)" }
  ghost = ev[:ghost].map { |t, v| "between(t,#{t},#{t+0.09})*#{v}*exp(-(t-#{t})*35)" }
  hat = ev[:hat].map { |t, v| "between(t,#{t},#{t+0.06})*#{v}*exp(-(t-#{t})*78)" }
  open = ev[:open].map { |t, v| "between(t,#{t},#{t+0.25})*#{v}*exp(-(t-#{t})*11)" }
  pad = ev[:pad].each_with_index.map { |(t, v, chord, sustain), i| pad_expression(t, v, chord, sustain, i) }
  chop = ev[:chop].map do |t, v, chord|
    f = chord[(t * 10).to_i % chord.length]
    "between(t,#{t},#{t+0.55})*#{v}*0.11*exp(-(t-#{t})*1.7)*(sin(2*PI*#{f}*(t-#{t}))+0.35*sin(2*PI*#{f*1.5}*(t-#{t})))"
  end
  risers = ev[:riser].map { |t, v| "between(t,#{t},#{t+2.0})*#{v}*((t-#{t})/2.0)^2" }
  stops = ev[:stop].map { |t, v| "between(t,#{t},#{t+1.1})*#{v}*exp(-(t-#{t})*2.2)" }

  inputs = [
    *lavfi("aevalsrc='#{expr(kick)}':d=#{dur}:s=#{SR}"),
    *lavfi("aevalsrc='#{expr(bass)}':d=#{dur}:s=#{SR}"),
    *lavfi("anoisesrc=color=white:r=#{SR}:amplitude=0.5:d=#{dur}"),
    *lavfi("anoisesrc=color=pink:r=#{SR}:amplitude=0.04:d=#{dur}"),
    *lavfi("aevalsrc='#{expr(pad)}':d=#{dur}:s=#{SR}"),
    *lavfi("aevalsrc='#{expr(chop)}':d=#{dur}:s=#{SR}"),
    *lavfi("aevalsrc='#{expr(risers + stops)}':d=#{dur}:s=#{SR}")
  ]

  filter = <<~F
    [0:a]aformat=channel_layouts=stereo[k];
    [1:a]aformat=channel_layouts=stereo,lowpass=f=140[bs];
    [2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no];
    [ns]volume='#{expr(snare + ghost)}':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[sn];
    [nh]volume='#{expr(hat)}':eval=frame,highpass=f=6500[hh];
    [no]volume='#{expr(open)}':eval=frame,bandpass=f=5600:w=5200[op];
    [4:a]aformat=channel_layouts=stereo,lowpass=f=#{ANALOG[:lowpass_hz]},aphaser=speed=0.08:decay=0.35,adelay=#{ANALOG[:chorus_delay_l_ms]}|#{ANALOG[:chorus_delay_r_ms]},aecho=0.18:0.22:120:0.22[pad];
    [5:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop];
    [6:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=9000[fx];
    [k][bs][sn][hh][op][pad][chop][fx]amix=inputs=8:weights=1.25 0.9 0.9 0.48 0.42 0.95 0.65 0.35:duration=longest[music];
    [3:a]volume=#{ANALOG[:vinyl_level]},highpass=f=90,lowpass=f=8000[vinyl];
    [music][vinyl]amix=inputs=2:weights=1 0.32:duration=first,
      acompressor=threshold=-18dB:ratio=3.5:attack=25:release=120:makeup=2,
      acrusher=bits=#{ANALOG[:sp_bits]}:samples=#{ANALOG[:sp_ratio].round(3)}:mix=0.22,
      aeval='(tanh((val(0)+#{ANALOG[:tape_dc]})*1.45)-0.072)/0.87|(tanh((val(1)+#{ANALOG[:tape_dc]})*1.45)-0.072)/0.87',
      highpass=f=30,lowpass=f=12000,equalizer=f=45:t=o:w=1.2:g=1,
      alimiter=level_out=0.96:limit=0.92[out]
  F

  codec = File.extname(dest).downcase == ".mp3" ? ["-codec:a", "libmp3lame", "-b:a", "320k"] : ["-c:a", "pcm_s16le"]
  FileUtils.mkdir_p(File.dirname(dest))
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filter.tr("\n", " "), "-map", "[out]", *codec, dest
end

def liveset(dest, minutes)
  bars = [(minutes.to_f * 60.0 / (60.0 / BPM * 4)).ceil, 64].max
  render(dest, bars: bars)
end

def clean(input, output)
  abort "missing input" unless input && File.exist?(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-i", input, "-af", "highpass=f=28,lowpass=f=15500,afftdn=nf=-25,adeclick,loudnorm=I=-18:TP=-1.5:LRA=10", "-c:a", "pcm_s16le", output
end

def stems(root, manifest)
  sets = []
  Dir.glob(File.join(root, "**", "*.{wav,mp3,flac,ogg,m4a}"), File::FNM_EXTGLOB).group_by { |p| File.dirname(p) }.each do |dir, files|
    stem_map = {}
    files.each do |f|
      b = File.basename(f).downcase
      key = b.include?("drums") ? "drums" : b.include?("bass") ? "bass" : b.include?("vocals") ? "vocals" : b.include?("other") ? "other" : File.basename(f, ".*")
      stem_map[key] = f.sub(DIR + "/", "")
    end
    sets << { "name" => File.basename(dir), "bpm" => BPM, "stems" => stem_map, "prime_swell" => PRIMES[sets.length % PRIMES.length] }
  end
  FileUtils.mkdir_p(File.dirname(manifest))
  File.write(manifest, JSON.pretty_generate({ "version" => 4, "sets" => sets }) + "\n")
  puts "manifest -> #{manifest}"
end

def chords
  PAD_CHORDS.each_with_index { |c, i| puts "%02d %-10s %s" % [i + 1, c[:name], c[:hz].map { |x| x.round(2) }.join(" ")] }
end

case ARGV.shift
when "render", nil then render(ARGV.shift || File.join(DIR, "analog_full.mp3"))
when "liveset" then liveset(ARGV.shift || File.join(DIR, "analog_liveset.mp3"), (ARGV.shift || 12).to_f)
when "clean" then clean(ARGV.shift, ARGV.shift || File.join(DIR, "samples/clean.wav"))
when "stems" then stems(ARGV.shift || File.join(DIR, "samples/demucs"), ARGV.shift || File.join(DIR, "samples/manifest.json"))
when "chords" then chords
else puts "render OUT.mp3 | liveset OUT.mp3 MINUTES | chords | clean IN OUT | stems ROOT MANIFEST"
end
