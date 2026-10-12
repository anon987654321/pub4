#!/usr/bin/env ruby
# dilla.rb — radically simplified J Dilla–style generator.
#
# Usage:
#   ruby dilla.rb --list
#   ruby dilla.rb --progression sv_intro --out out/sv_intro.wav
#   ruby dilla.rb --progression sv_intro --drums boom_bap --out out/full.wav
#   ruby dilla.rb --quick
#
# Reads dilla.json (same directory). Writes 16-bit mono 44.1kHz WAV.

require 'json'
require 'optparse'
require 'fileutils'

SAMPLE_RATE = 44_100

# ---------------------------------------------------------------- WAV writer
module WAV
  def self.write(path, samples)
    data = samples.map { |s| (s * 32767).round.clamp(-32_768, 32_767) }.pack('s<*')

    header  = +"RIFF"
    header << [36 + data.bytesize].pack('V')
    header << "WAVE"
    header << "fmt "
    header << [16].pack('V')
    header << [1].pack('v')                    # PCM
    header << [1].pack('v')                    # mono
    header << [SAMPLE_RATE].pack('V')
    header << [SAMPLE_RATE * 2].pack('V')      # byte rate
    header << [2].pack('v')                    # block align
    header << [16].pack('v')                   # bits per sample
    header << "data"
    header << [data.bytesize].pack('V')

    File.binwrite(path, header + data)
  end
end

# --------------------------------------------------------------- synthesis
module Synth
  def self.env(t, dur, attack: 0.01, release: 0.3)
    if t < attack
      t / attack
    elsif t > dur - release
      [(dur - t) / release, 0.0].max
    else
      1.0
    end
  end

  # One note = sum of four harmonics with optional per-note detune.
  def self.note(freq, dur, detune: 0.0, amp: 0.2)
    n = (dur * SAMPLE_RATE).to_i
    out = Array.new(n, 0.0)
    partials = [[1.0, 1.0], [2.0, 0.35], [3.0, 0.15], [4.0, 0.08]]

    partials.each do |mult, pamp|
      f = freq * mult * (1.0 + detune)
      phase = 0.0
      step = 2 * Math::PI * f / SAMPLE_RATE
      n.times do |i|
        t = i.to_f / SAMPLE_RATE
        out[i] += Math.sin(phase) * pamp * env(t, dur)
        phase += step
      end
    end
    out.map { |s| s * amp }
  end

  # One chord = sum of its notes, each with alternating detune for warmth.
  def self.chord(freqs, dur, detune: 0.0)
    n = (dur * SAMPLE_RATE).to_i
    buf = Array.new(n, 0.0)
    freqs.each_with_index do |f, idx|
      d = detune * (idx.even? ? 1 : -1)
      note_buf = note(f, dur, detune: d, amp: 1.0 / freqs.size)
      note_buf.each_with_index { |s, i| buf[i] += s if i < n }
    end
    buf
  end
end

# ------------------------------------------------------------------- drums
module Drums
  def self.kick(dur = 0.25)
    n = (dur * SAMPLE_RATE).to_i
    out = Array.new(n)
    n.times do |i|
      t = i.to_f / SAMPLE_RATE
      f = 80 * Math.exp(-t * 30) + 40
      out[i] = Math.sin(2 * Math::PI * f * t) * Math.exp(-t * 12) * 0.9
    end
    out
  end

  def self.snare(dur = 0.20)
    n = (dur * SAMPLE_RATE).to_i
    out = Array.new(n)
    n.times do |i|
      t = i.to_f / SAMPLE_RATE
      noise = rand * 2 - 1
      tone  = Math.sin(2 * Math::PI * 180 * t)
      out[i] = (noise * 0.7 + tone * 0.3) * Math.exp(-t * 25) * 0.7
    end
    out
  end

  def self.hat(dur = 0.06)
    n = (dur * SAMPLE_RATE).to_i
    out = Array.new(n)
    n.times do |i|
      t = i.to_f / SAMPLE_RATE
      out[i] = (rand * 2 - 1) * Math.exp(-t * 90) * 0.3
    end
    out
  end
end

# ---------------------------------------------------------------------- FX
module FX
  def self.lowpass(buf, cutoff)
    return buf if cutoff.nil?
    rc = 1.0 / (2 * Math::PI * cutoff)
    dt = 1.0 / SAMPLE_RATE
    a  = dt / (rc + dt)
    y  = 0.0
    buf.map { |x| y += a * (x - y); y }
  end

  def self.reverb(buf, amount)
    return buf if amount.nil? || amount <= 0
    delays = [0.0297, 0.0371, 0.0411, 0.0437].map { |d| (d * SAMPLE_RATE).to_i }
    gains  = [0.70, 0.65, 0.60, 0.55]
    out = buf.dup
    delays.each_with_index do |d, k|
      i = d
      while i < out.size
        out[i] += out[i - d] * gains[k] * amount
        i += 1
      end
    end
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |s| s / peak } : out
  end

  def self.apply(buf, preset)
    return buf if preset.nil?
    b = buf
    b = lowpass(b, preset['lowpass']) if preset['lowpass']
    b = reverb(b, preset['reverb'])   if preset['reverb']
    b
  end
end

# --------------------------------------------------------------- sequencer
class Sequencer
  def initialize(data)
    @data = data
  end

  def render_progression(key)
    prog = @data['progressions'][key] or abort "No progression: #{key}"
    tempo    = prog['tempo']    || 90
    beats    = prog['duration'] || 2.0
    fx_name  = prog['fx']
    fx       = @data['fx'][fx_name]
    detune   = (fx && fx['detune']) || 0.0
    swing    = (fx && fx['swing'])  || 0.5

    beat      = 60.0 / tempo
    chord_dur = beats * beat

    buf = []
    prog['freqs'].each_with_index do |freqs, idx|
      delay = (idx.even? ? 0.0 : (swing - 0.5) * beat)
      pad   = (delay * SAMPLE_RATE).to_i
      buf.concat(Array.new(pad, 0.0)) if pad > 0
      buf.concat(Synth.chord(freqs, chord_dur, detune: detune))
    end

    buf = FX.apply(buf, fx) if fx
    buf
  end

  def overlay_drums(chord_buf, drum_key, tempo)
    pat = @data['drums'][drum_key] or return chord_buf
    beat = 60.0 / tempo
    step = beat / 4.0
    total = chord_buf.size
    out = chord_buf.dup

    sources = { 'kick' => Drums.kick, 'snare' => Drums.snare, 'hat' => Drums.hat }
    sources.each do |name, sound|
      pattern = pat[name] || []
      pattern.each_with_index do |hit, i|
        next if hit.to_i.zero?
        start = (i * step * SAMPLE_RATE).to_i
        sound.each_with_index do |s, j|
          idx = start + j
          break if idx >= total
          out[idx] += s * 0.8
        end
      end
    end

    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |s| s / peak } : out
  end
end

# ---------------------------------------------------------------------- CLI
options = {}
OptionParser.new do |o|
  o.banner = "Usage: ruby dilla.rb [options]"
  o.on('--list',                    'List progressions')      { options[:list] = true }
  o.on('--progression NAME',        'Progression key')        { |v| options[:prog] = v }
  o.on('--drums NAME',              'Drum pattern key')       { |v| options[:drums] = v }
  o.on('--out PATH',                'Output WAV path')        { |v| options[:out] = v }
  o.on('--quick',                   'Render first progression as smoke test') { options[:quick] = true }
end.parse!

data_path = File.join(__dir__, 'dilla.json')
data = JSON.parse(File.read(data_path))

if options[:list] || (options[:prog].nil? && !options[:quick])
  puts "Progressions:"
  data['progressions'].each do |k, v|
    puts "  #{k.ljust(20)} #{v['name']} (#{v['artist']})"
  end
  puts
  puts "Drum patterns: #{data['drums'].keys.join(', ')}"
  puts "FX presets:    #{data['fx'].keys.join(', ')}"
  exit
end

seq = Sequencer.new(data)

if options[:quick]
  key = data['progressions'].keys.first
  buf = seq.render_progression(key)
  FileUtils.mkdir_p('out')
  WAV.write('out/quick.wav', buf)
  puts "Wrote out/quick.wav (#{buf.size} samples, #{(buf.size / SAMPLE_RATE.to_f).round(2)}s)"
  exit
end

key   = options[:prog]
tempo = data['progressions'][key]['tempo'] || 90

buf = seq.render_progression(key)
buf = seq.overlay_drums(buf, options[:drums], tempo) if options[:drums]

out_path = options[:out] || "out/#{key}#{options[:drums] ? "_#{options[:drums]}" : ''}.wav"
FileUtils.mkdir_p(File.dirname(out_path))
WAV.write(out_path, buf)
puts "Wrote #{out_path} (#{(buf.size / SAMPLE_RATE.to_f).round(2)}s, #{buf.size} samples)"
