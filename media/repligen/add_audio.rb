#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick script to add audio to ME2 catwalk video

video = ARGV[0] || raise("Provide video path")

audio = ARGV[1] || raise("Provide audio path")

output = ARGV[2] || video.gsub(".mp4", "_audio.mp4")

cmd = "ffmpeg -i "#{video}" -i "#{audio}" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "#{output}" -y"

puts "🎵 Adding audio to video..."

puts "Video: #{File.basename(video)}"

puts "Audio: #{File.basename(audio)}"

puts "Output: #{File.basename(output)}"

system(cmd)

if File.exist?(output)

  puts "✓ Complete: #{output}"

else

  puts "✗ Failed"

end

