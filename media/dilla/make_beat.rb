#!/usr/bin/env ruby
# Quick beat builder using available samples
require 'fileutils'

# Files we have
KICK = "808_bd_medium_r8_t1a.wav"
SNARE = "808_sd_jd800_01.wav"
HIHAT = "808_hh_jd800.wav"
SAMPLE = "R-Mårdalen R.aif"

BPM = 95
BARS = 4
BEAT_DURATION = (60.0 / BPM) * 4 * BARS  # seconds

puts "🎹 Building Dilla-style beat at #{BPM} BPM"
puts "Duration: #{BEAT_DURATION}s (#{BARS} bars)"

# Convert .aif to .wav first
puts "\n1️⃣  Converting sample..."
system("ffmpeg -y -i \"#{SAMPLE}\" -ar 48000 sample.wav 2>&1 | tail -5")

# Create drum pattern files using adelay filter
# Pattern: Dilla swing - kick on 1,3 (slightly early/late), snare on 2,4 (pushed)
puts "\n2️⃣  Creating drum pattern..."

# Kick pattern: beats 1 and 3 (0ms, 1000ms with -8ms nudge)
kick_times = [0, 2000 - 8]  # 2 bars worth, ms
kick_delays = kick_times.map { |t| "#{t}|#{t}" }.join("|")

# Build the beat step by step
system("ffmpeg -y -i \"#{KICK}\" -af \"adelay=#{kick_delays}\" kick_pattern.wav 2>&1 | tail -3")

puts "\n✅ Beat components ready!"
puts "Next: Mix layers with dilla.rb or manual FFmpeg commands"
