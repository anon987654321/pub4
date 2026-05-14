#!/usr/bin/env ruby
# frozen_string_literal: true
# dilla.rb — audible full-track render command + Demucs workflow.
# Commands:
#   ruby dilla/dilla.rb render dilla/full_track.mp3
#   ruby dilla/dilla.rb clean input.wav output.wav
#   ruby dilla/dilla.rb stems dilla/samples/demucs dilla/samples/manifest.json
#
# Original primitive synthesis only. No YouTube downloading.

require "json"
require "fileutils"

BPM = (ENV["BPM"] || 86).to_f
BARS = (ENV["BARS"] || 88).to_i
DIR = File.expand_path(__dir__)

def sh!(*cmd)
  puts ">>> #{cmd.flatten.join(' ')}"
  abort "failed" unless system(*cmd.flatten.map(&:to_s))
end

def lavfi(s) = ["-f", "lavfi", "-i", s]
def expr(a) = a.empty? ? "0" : a.join("+")

def render(dest)
  beat = 60.0 / BPM
  bar = beat * 4
  step = bar / 16
  dur = (BARS * bar).round(3)
  kicks = []
  snares = []
  ghosts = []
  hats = []
  opens = []
  bass = []
  roots = [43.65, 49.0, 51.91, 38.89, 46.25]
  pats = [[0,7,10,14], [0,5,7,10,14], [0,3,7,10,12,14], [0,6,9,14]]

  BARS.times do |b|
    sec = b < 8 ? :intro : b < 24 ? :a : b < 40 ? :a2 : b < 48 ? :break : b < 64 ? :b : b < 72 ? :drop : :outro
    den = sec == :intro ? 0.45 : sec == :break ? 0.55 : sec == :drop ? 0.72 : 1.0
    kp = pats[(b / 8 + b % 3) % pats.length].dup
    kp = [0,3,6,7,10,12,14,15] if b % 16 == 15
    kp = [0,10] if sec == :intro && b > 2
    kp = [] if sec == :intro && b <= 2
    kp = (b.even? ? [0] : [0,7]) if sec == :break
    kp = (b.even? ? [0,10] : [0,7,14]) if sec == :drop

    kp.each_with_index do |s, i|
      t = b * bar + s * step + [0, 0.006, 0.011, -0.004, 0.018][(b + i) % 5]
      kicks << [t, den]
      bass << [t + 0.020, den, roots[(b / 4 + i) % roots.length]] unless sec == :intro
    end

    [4, 12].each { |s| snares << [b * bar + s * step + [-0.010, -0.006, 0.004, 0.010, 0.017][b % 5], den] unless sec == :intro }
    (b.even? ? [6,11] : [3,6,11,15]).each { |s| ghosts << [b * bar + s * step, den * 0.35] unless [:intro, :drop].include?(sec) }

    hs = b % 16 == 7 ? [0,4,8,12] : [0,2,4,6,8,10,12,14]
    hs = [] if sec == :break && b.even?
    hs.each_with_index { |s, i| hats << [b * bar + s * step + (i.odd? ? 0.018 : 0.002), den * 0.55] }
    opens << [b * bar + 6 * step + 0.008, den * 0.32] if ![:intro, :break].include?(sec) && [1,3].include?(b % 4)
  end

  k = kicks.map { |t, v| "between(t,#{t},#{t + 0.42})*#{v}*0.95*exp(-(t-#{t})*7.4)*sin(2*PI*(45+115*exp(-20*(t-#{t})))*(t-#{t}))" }
  b = bass.map { |t, v, f| "between(t,#{t},#{t + 0.44})*#{v}*0.42*exp(-(t-#{t})*3.2)*sin(2*PI*#{f}*(t-#{t}))" }
  s = snares.map { |t, v| "between(t,#{t},#{t + 0.18})*#{v}*0.6*exp(-(t-#{t})*23)" }
  g = ghosts.map { |t, v| "between(t,#{t},#{t + 0.09})*#{v}*exp(-(t-#{t})*35)" }
  h = hats.map { |t, v| "between(t,#{t},#{t + 0.06})*#{v}*exp(-(t-#{t})*78)" }
  o = opens.map { |t, v| "between(t,#{t},#{t + 0.25})*#{v}*exp(-(t-#{t})*11)" }

  inputs = [
    *lavfi("aevalsrc='#{expr(k)}':d=#{dur}:s=44100"),
    *lavfi("aevalsrc='#{expr(b)}':d=#{dur}:s=44100"),
    *lavfi("anoisesrc=color=white:r=44100:amplitude=0.5:d=#{dur}"),
    *lavfi("anoisesrc=color=pink:r=44100:amplitude=0.04:d=#{dur}")
  ]

  filt = "[0:a]aformat=channel_layouts=stereo[k];" \
         "[1:a]aformat=channel_layouts=stereo,lowpass=f=140[bs];" \
         "[2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no];" \
         "[ns]volume='#{expr(s + g)}':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[sn];" \
         "[nh]volume='#{expr(h)}':eval=frame,highpass=f=6500[hh];" \
         "[no]volume='#{expr(o)}':eval=frame,bandpass=f=5600:w=5200[op];" \
         "[k][bs][sn][hh][op]amix=inputs=5:weights=1.3 0.9 0.9 0.5 0.45:duration=longest[m];" \
         "[3:a]volume=0.13,highpass=f=100,lowpass=f=8000[v];" \
         "[m][v]amix=inputs=2:weights=1 0.35:duration=first," \
         "acompressor=threshold=-18dB:ratio=3.5:attack=18:release=95:makeup=2," \
         "acrusher=bits=12:samples=1.69:mix=0.18,highpass=f=30,lowpass=f=12000," \
         "alimiter=level_out=0.96:limit=0.92[out]"

  codec = File.extname(dest) == ".mp3" ? ["-codec:a", "libmp3lame", "-b:a", "320k"] : ["-c:a", "pcm_s16le"]
  FileUtils.mkdir_p(File.dirname(dest))
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filt, "-map", "[out]", *codec, dest
end

def clean(input, output)
  abort "missing input" unless input && File.exist?(input)
  sh! "ffmpeg", "-y", "-i", input, "-af", "highpass=f=28,lowpass=f=15500,afftdn=nf=-25,adeclick,loudnorm=I=-18:TP=-1.5:LRA=10", "-c:a", "pcm_s16le", output
end

def stems(root, manifest)
  sets = []
  Dir.glob(File.join(root, "**", "*.{wav,mp3,flac,ogg,m4a}"), File::FNM_EXTGLOB).group_by { |p| File.dirname(p) }.each do |dir, files|
    stem_map = {}
    files.each do |f|
      b = File.basename(f).downcase
      k = b.include?("drums") ? "drums" : b.include?("bass") ? "bass" : b.include?("vocals") ? "vocals" : b.include?("other") ? "other" : File.basename(f, ".*")
      stem_map[k] = f.sub(DIR + "/", "")
    end
    sets << { "name" => File.basename(dir), "bpm" => BPM, "stems" => stem_map }
  end
  FileUtils.mkdir_p(File.dirname(manifest))
  File.write(manifest, JSON.pretty_generate({ "version" => 2, "sets" => sets }) + "\n")
end

case ARGV.shift
when "render", nil then render(ARGV.shift || File.join(DIR, "full_track.mp3"))
when "clean" then clean(ARGV.shift, ARGV.shift || File.join(DIR, "clean.wav"))
when "stems" then stems(ARGV.shift || File.join(DIR, "samples/demucs"), ARGV.shift || File.join(DIR, "samples/manifest.json"))
else
  puts "ruby dilla.rb render out.mp3 | clean in.wav out.wav | stems demucs_dir manifest.json"
end
