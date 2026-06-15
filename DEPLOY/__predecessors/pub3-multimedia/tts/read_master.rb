#!/usr/bin/env ruby
# frozen_string_literal: true

# Read master.json summary with gTTS

text = "Master JSON version 337.3.0. Governance for billion user apps. Platform OpenBSD 7.7. VPS architecture: internet to PF to relayd to Falcon to Rails. Key principles: internalize blocks all operations, ultraminimal second. Zero trust security. Rails 8 with Hotwire. Production deployment includes 7 apps: brgen on port 11006, amber on port 10001, blognet on port 10002, bsdports on port 10003, hjerterom on port 10004, privcam on port 10005, and pubattorney on port 10006."

output_file = "G:/pub/tts/master_summary.mp3"

# Generate MP3 with gTTS (Indian English accent)
python_exe = "C:/Users/aiyoo/AppData/Local/Programs/Python/Python313/python.exe"
cmd = %{"#{python_exe}" -c "from gtts import gTTS; tts = gTTS('#{text.gsub("'", "\\\\'")}', lang='en', tld='co.in'); tts.save('#{output_file}')"}

puts "Generating audio with gTTS..."
system(cmd)

if File.exist?(output_file)
  puts "✓ Audio saved to #{output_file}"
  puts "Playing..."
  system("start /min #{output_file}")
else
  warn "✗ Failed to generate audio"
  exit 1
end
