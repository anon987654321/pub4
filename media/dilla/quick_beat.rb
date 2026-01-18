#!/usr/bin/env ruby
# Minimal Dilla beat maker

KICK = "808_bd_medium_r8_t1a.wav"
SNARE = "808_sd_jd800_01.wav"
HIHAT = "808_hh_jd800.wav"
SAMPLE = "R-Mårdalen R.aif"

BPM = 95
BARS = 8
DURATION = (60.0 / BPM) * 4 * BARS

puts "Building beat: #{BPM} BPM, #{BARS} bars, #{DURATION.round(1)}s"

# Step 1: Convert sample
puts "\n1. Converting sample..."
system("/usr/bin/ffmpeg -y -i \"#{SAMPLE}\" -t #{DURATION} -ar 48000 -ac 2 sample.wav")

# Step 2: Apply SP-1200 character
puts "\n2. Applying SP-1200..."
system("/usr/bin/ffmpeg -y -i sample.wav -af \"acrusher=bits=12:mode=lin,volume=1.8,atanh,volume=0.555,lowpass=f=10000\" sample_sp.wav")

# Step 3: Create simple drum pattern
puts "\n3. Creating drums..."
kick_pattern = "0|0:2528|2528:5056|5056:7584|7584:10112|10112:12640|12640:15168|15168:17696|17696"
system("/usr/bin/ffmpeg -y -f lavfi -i anullsrc=duration=#{DURATION}:sample_rate=48000:channel_layout=stereo -i #{KICK} -filter_complex \"[1:a]adelay=#{kick_pattern}[k];[0:a][k]amix\" drums.wav")

# Step 4: Mix
puts "\n4. Mixing..."
system("/usr/bin/ffmpeg -y -i sample_sp.wav -i drums.wav -filter_complex \"[0:a][1:a]amix=inputs=2:duration=longest\" mix.wav")

# Step 5: Master
puts "\n5. Mastering..."
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
final = "DILLA_BEAT_#{timestamp}.wav"
system("/usr/bin/ffmpeg -y -i mix.wav -af \"loudnorm=I=-16\" #{final}")

# Cleanup
File.delete("sample.wav", "sample_sp.wav", "drums.wav", "mix.wav") rescue nil

puts "\n✅ DONE: #{final}"
