#!/usr/bin/env ruby
# say.rb - Default TTS command using STRANGE VOICE
# Maximum weirdness as the new default!

require 'fileutils'

CACHE_DIR = 'G:/pub/multimedia/tts/strange_cache'
FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)

# Text corruption
def corrupt_text(text)
  words = text.split(' ')
  glitches = ['*bzzt*', '*crackle*', '*static*', '*pop*', '*glitch*']
  
  result = []
  words.each do |word|
    # Add glitch sound (40% chance)
    result << glitches.sample if rand < 0.4
    
    # Stutter (40% chance)
    if rand < 0.4 && word.length > 1
      first = word[0]
      result << "#{first}-#{first}-#{first}-#{word}"
    else
      result << word
    end
    
    # Repeat word (30% chance)
    result << word if rand < 0.3
  end
  
  result.join(' ')
end

# Random voice selection
def random_voice
  voices = [
    { voice: 'en+croak', pitch: 0, speed: 60 },
    { voice: 'en+whisper', pitch: 99, speed: 300 },
    { voice: 'en+m3', pitch: 10, speed: 100 },
    { voice: 'en+f4', pitch: 80, speed: 220 },
    { voice: 'en+croak', pitch: 40, speed: 150 }
  ]
  voices.sample
end

# Main
text = ARGV.join(' ')
text = "Hello from the strange voice system" if text.empty?

corrupted = corrupt_text(text)
puts "[CORRUPTED] #{corrupted}"

voice = random_voice
temp_wav = "#{CACHE_DIR}/say_#{Time.now.to_i}.wav"
cygwin_path = "/cygdrive/g/pub/multimedia/tts/strange_cache/say_#{Time.now.to_i}.wav"

# Generate with espeak
cmd = "espeak -v #{voice[:voice]} -p #{voice[:pitch]} -s #{voice[:speed]} -w #{cygwin_path} \"#{corrupted.gsub('"', '\\"')}\" 2>/dev/null"
system("C:/cygwin64/bin/bash.exe", "-l", "-c", cmd)

# Play with PowerShell
if File.exist?(temp_wav)
  ps = <<~PS
    Add-Type -AssemblyName System.Windows.Forms
    $player = New-Object System.Media.SoundPlayer('#{temp_wav.gsub('/', '\\')}')
    $player.PlaySync()
  PS
  
  system("powershell.exe", "-Command", ps)
  File.delete(temp_wav) if File.exist?(temp_wav)
end
