#!/usr/bin/env ruby
# Real Dilla beat maker - over 1 minute, full mix only
require 'fileutils'

KICK = "808_bd_medium_r8_t1a.wav"
SNARE = "808_sd_jd800_01.wav"
HIHAT = "808_hh_jd800.wav"
SAMPLE = "R-Mårdalen R.aif"

BPM = 95
BARS = 8  # Over 1 minute
BEAT_MS = (60.0 / BPM * 1000).round  # 632ms per beat
BAR_MS = BEAT_MS * 4  # 2528ms per bar
DURATION = BARS * BAR_MS / 1000.0  # seconds

puts "🎹 DILLA BEAT MAKER"
puts "BPM: #{BPM} | Bars: #{BARS} | Duration: #{DURATION.round(1)}s"

# Dilla swing offsets (from dilla.rb config)
SWING = { kick: -8, snare: 12, hihat: -3 }

# Build filter complex for full beat
def build_drums
  inputs = []
  filters = []
  mix_inputs = []
  
  # Create silence base
  filters << "[0:a]aeval=val(0):duration=#{DURATION}[silence]"
  
  # KICK - beats 1,3 of each bar
  kick_delays = (0...BARS).flat_map { |bar| 
    base = bar * BAR_MS
    [base + SWING[:kick], base + (BEAT_MS * 2) + SWING[:kick]]
  }
  kick_delays.each_with_index do |delay, i|
    filters << "[1:a]adelay=#{delay}|#{delay}[k#{i}]"
    mix_inputs << "[k#{i}]"
  end
  
  # SNARE - beats 2,4 of each bar
  snare_delays = (0...BARS).flat_map { |bar|
    base = bar * BAR_MS
    [base + BEAT_MS + SWING[:snare], base + (BEAT_MS * 3) + SWING[:snare]]
  }
  snare_delays.each_with_index do |delay, i|
    filters << "[2:a]adelay=#{delay}|#{delay}[s#{i}]"
    mix_inputs << "[s#{i}]"
  end
  
  # HIHAT - 16th notes, varied velocity
  sixteenth = BEAT_MS / 4.0
  hihat_pattern = [1.0, 0.7, 0.5, 0.7]  # Velocity pattern
  hihat_delays = []
  (0...(BARS * 16)).each do |i|
    delay = (i * sixteenth + SWING[:hihat]).round
    vel = hihat_pattern[i % 4]
    filters << "[3:a]volume=#{vel},adelay=#{delay}|#{delay}[h#{i}]"
    mix_inputs << "[h#{i}]"
  end
  
  # Mix all drums
  all_inputs = "[silence]" + mix_inputs.join
  filters << "#{all_inputs}amix=inputs=#{mix_inputs.length + 1}:duration=longest[drums]"
  
  filters.join(';')
end

puts "\n1️⃣  Converting sample..."
system("ffmpeg -y -i \"#{SAMPLE}\" -t #{DURATION} -ar 48000 -ac 2 .sample.wav 2>&1 | grep -E 'Duration|Output'")

puts "\n2️⃣  Applying SP-1200 character to sample..."
system("ffmpeg -y -i .sample.wav -af \"acrusher=bits=12:mode=lin,volume=1.8,atanh,volume=0.555,lowpass=f=10000,volume=0.6\" .sample_proc.wav 2>&1 | grep Output")

puts "\n3️⃣  Building drum pattern with Dilla swing..."
drum_filter = build_drums
system("ffmpeg -y -i .sample_proc.wav -i #{KICK} -i #{SNARE} -i #{HIHAT} -filter_complex \"#{drum_filter}\" -map '[drums]' .drums.wav 2>&1 | grep Output")

puts "\n4️⃣  Mixing sample + drums..."
system("ffmpeg -y -i .sample_proc.wav -i .drums.wav -filter_complex \"[0:a][1:a]amix=inputs=2:duration=longest[mix]\" -map '[mix]' .mix.wav 2>&1 | grep Output")

puts "\n5️⃣  Mastering (MPC3000 character + compression)..."
master_chain = "acrusher=bits=14:mode=lin,volume=1.2,atanh,volume=0.833,acompressor=threshold=-18dB:ratio=4:attack=5:release=50,equalizer=f=100:width_type=q:width=0.8:g=3,equalizer=f=8000:width_type=q:width=1.2:g=-2.5,loudnorm=I=-16:TP=-1"
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
final = "DILLA_BEAT_#{BPM}BPM_#{timestamp}.wav"
system("ffmpeg -y -i .mix.wav -af \"#{master_chain}\" #{final} 2>&1 | grep Output")

puts "\n6️⃣  Cleaning up..."
['.sample.wav', '.sample_proc.wav', '.drums.wav', '.mix.wav'].each { |f| File.delete(f) if File.exist?(f) }

puts "\n✅ DONE: #{final}"
puts "Duration: #{DURATION.round(1)}s (#{BARS} bars at #{BPM} BPM)"
puts "Dilla swing: kick #{SWING[:kick]}ms, snare +#{SWING[:snare]}ms, hihat #{SWING[:hihat]}ms"
