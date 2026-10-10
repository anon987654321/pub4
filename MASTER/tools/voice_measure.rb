#!/usr/bin/env ruby
# frozen_string_literal: true

# What a voice clip measures, in numbers an ear can be checked against.
#
#   ruby MASTER/tools/voice_measure.rb clip.mp3 [--words N | --text "spoken text"]
#   ruby MASTER/tools/voice_measure.rb --selfcheck
#
# Per clip: integrated loudness and range (ffmpeg ebur128), speech rate in
# words per second of speech and of the whole clip (silencedetect), the pause
# length distribution (silences between speech, edges excluded), pitch movement
# and energy movement.
#
# Pitch: no installed command-line tool gives F0 (aubio, crepe absent; sox has
# no tracker; ffmpeg has none). The F0 here is this file's own
# autocorrelation tracker on 8 kHz mono, voiced frames only, so it is an
# estimate: good for comparing clips, not an absolute pitch. Energy movement is
# the standard deviation of 50 ms frame RMS in dB over voiced frames, which
# needs no tracker and is reported beside it.
#
# --selfcheck is the instrument's own proof: a steady tone must show almost no
# pitch movement and a swept tone a lot, and it must find a known pause.

require "open3"
require "json"
require "tmpdir"

module VoiceMeasure
  SILENCE_DB = -38
  SILENCE_MIN_S = 0.12
  RATE = 8000
  FRAME = 240
  HOP = 80
  MIN_F0 = 70
  MAX_F0 = 400

  module_function

  def ffmpeg(*args)
    Open3.capture3("ffmpeg", "-hide_banner", "-nostats", *args)
  end

  def duration(path)
    out, _err, status = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path)
    status.success? ? out.to_f : 0.0
  end

  def loudness(path)
    _out, err, = ffmpeg("-i", path, "-af", "ebur128=peak=true", "-f", "null", "-")
    summary = err.split("Summary:").last.to_s
    {
      lufs: summary[/I:\s+(-?[\d.]+) LUFS/, 1]&.to_f,
      lra: summary[/LRA:\s+(-?[\d.]+) LU/, 1]&.to_f,
      true_peak_db: summary[/Peak:\s+(-?[\d.]+) dBFS/, 1]&.to_f,
    }
  end

  def silences(path, total)
    _out, err, = ffmpeg("-i", path, "-af", "silencedetect=noise=#{SILENCE_DB}dB:d=#{SILENCE_MIN_S}", "-f", "null", "-")
    starts = err.scan(/silence_start: (-?[\d.]+)/).flatten.map(&:to_f)
    ends = err.scan(/silence_end: (-?[\d.]+)/).flatten.map(&:to_f)
    starts.each_with_index.map { |s, i| [[s, 0.0].max, ends[i] || total] }
  end

  def percentile(sorted, fraction)
    return if sorted.empty?

    sorted[((sorted.size - 1) * fraction).round]
  end

  def timing(path, words)
    total = duration(path)
    gaps = silences(path, total)
    lead = gaps.first && gaps.first[0] <= 0.02 ? gaps.first[1] - gaps.first[0] : 0.0
    trail = gaps.last && gaps.last[1] >= total - 0.02 ? gaps.last[1] - gaps.last[0] : 0.0
    inner = gaps.reject { |s, e| s <= 0.02 || e >= total - 0.02 }.map { |s, e| e - s }.sort
    speech = total - gaps.sum { |s, e| e - s }
    {
      duration_s: total.round(2),
      speech_s: speech.round(2),
      words_per_s_speech: words && speech.positive? ? (words / speech).round(2) : nil,
      words_per_s_clip: words && total.positive? ? (words / (total - lead - trail)).round(2) : nil,
      pauses: {
        count: inner.size,
        mean_ms: inner.empty? ? nil : (inner.sum / inner.size * 1000).round,
        p50_ms: percentile(inner, 0.5)&.*(1000)&.round,
        p90_ms: percentile(inner, 0.9)&.*(1000)&.round,
        max_ms: inner.last&.*(1000)&.round,
      },
    }
  end

  def samples(path)
    pcm, status = Open3.capture2("ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", RATE.to_s, "-f", "s16le", "-", binmode: true)
    status.success? ? pcm.unpack("s<*").map { |v| v / 32_768.0 } : []
  end

  # Lag with the strongest normalised autocorrelation, or nil for unvoiced.
  def f0(frame)
    energy = frame.sum { |v| v * v }
    return if energy < 1e-4 * frame.size

    best = nil
    best_r = 0.0
    (RATE / MAX_F0..RATE / MIN_F0).each do |lag|
      sum = 0.0
      (0...(frame.size - lag)).each { |i| sum += frame[i] * frame[i + lag] }
      r = sum / energy
      next unless r > best_r

      best_r = r
      best = lag
    end
    best && best_r > 0.45 ? RATE.to_f / best : nil
  end

  def stddev(values)
    return if values.size < 3

    mean = values.sum / values.size
    Math.sqrt(values.sum { |v| (v - mean)**2 } / values.size)
  end

  def semitones(hz, ref) = 12 * Math.log2(hz / ref)

  def movement(path)
    data = samples(path)
    pitches = []
    levels = []
    (0..(data.size - FRAME)).step(HOP) do |offset|
      frame = data[offset, FRAME]
      rms = Math.sqrt(frame.sum { |v| v * v } / frame.size)
      next if rms < 0.005

      levels << 20 * Math.log10(rms)
      hz = f0(frame)
      pitches << hz if hz
    end
    median = pitches.sort[pitches.size / 2]
    st = median ? pitches.map { |hz| semitones(hz, median) } : []
    {
      voiced_frames: pitches.size,
      f0_median_hz: median&.round,
      f0_std_semitones: stddev(st)&.round(2),
      f0_range_semitones: st.empty? ? nil : (st.max - st.min).round(1),
      energy_std_db: stddev(levels)&.round(2),
    }
  end

  def measure(path, words: nil)
    { file: path, loudness: loudness(path), timing: timing(path, words), movement: movement(path) }
  end

  def selfcheck
    Dir.mktmpdir("voice_measure") do |dir|
      steady = File.join(dir, "steady.wav")
      swept = File.join(dir, "swept.wav")
      gapped = File.join(dir, "gapped.wav")
      ffmpeg("-y", "-f", "lavfi", "-i", "sine=f=150:d=3", steady)
      ffmpeg("-y", "-f", "lavfi", "-i", "aevalsrc=0.5*sin(2*PI*t*(130+35*t+40*sin(2*PI*1.2*t))):d=3:s=16000", swept)
      ffmpeg("-y", "-f", "lavfi", "-i", "sine=f=150:d=1", File.join(dir, "a.wav"))
      ffmpeg("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "0.6", File.join(dir, "s.wav"))
      ffmpeg("-y", "-i", File.join(dir, "a.wav"), "-i", File.join(dir, "s.wav"), "-i", File.join(dir, "a.wav"),
             "-filter_complex", "[0][1][2]concat=n=3:v=0:a=1", gapped)
      a = movement(steady)
      b = movement(swept)
      c = timing(gapped, 6)
      checks = {
        steady_is_flat: a[:f0_std_semitones].to_f < 0.5,
        swept_moves: b[:f0_std_semitones].to_f > 2.0,
        separated: b[:f0_std_semitones].to_f > 5 * [a[:f0_std_semitones].to_f, 0.1].max,
        finds_600ms_pause: c[:pauses][:count] == 1 && (500..700).cover?(c[:pauses][:max_ms].to_i),
      }
      { steady: a, swept: b, gapped: c, checks:, ok: checks.values.all? }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--selfcheck")
    result = VoiceMeasure.selfcheck
    puts JSON.pretty_generate(result)
    exit(result[:ok] ? 0 : 1)
  end

  words_at = ARGV.index("--words")
  text_at = ARGV.index("--text")
  words = if words_at
ARGV[words_at + 1].to_i
else
(text_at ? ARGV[text_at + 1].to_s.split.size : nil)
end
  files = ARGV.reject.with_index { |a, i| a.start_with?("--") || [words_at, text_at].compact.any? { |j| i == j + 1 } }
  abort("usage: voice_measure.rb clip [--words N | --text TEXT] | --selfcheck") if files.empty?
  files.each { |file| puts JSON.generate(VoiceMeasure.measure(file, words:)) }
end
