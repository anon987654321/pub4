#!/usr/bin/env ruby
# strange_voice.rb - VERY VERY strange voice with intentional imperfections
# Maximum weirdness + heavy lofi + glitchy artifacts
# Free, offline, independent

require 'fileutils'

# ============================================================================
# CONFIGURATION
# ============================================================================

STRANGE_CONFIG = {
  espeak: system('which espeak > /dev/null 2>&1'),
  sox: File.exist?('C:/cygwin64/bin/sox.exe') || system('which sox > /dev/null 2>&1'),
  cache_dir: 'G:/pub/multimedia/tts/strange_cache',
  glitch_probability: 0.4  # 40% chance of glitches
}

FileUtils.mkdir_p(STRANGE_CONFIG[:cache_dir]) unless Dir.exist?(STRANGE_CONFIG[:cache_dir])

# ============================================================================
# TEXT CORRUPTION - INTENTIONAL IMPERFECTIONS
# ============================================================================

class TextCorruptor
  def self.stutter(text, intensity: 0.3)
    words = text.split(' ')
    words.map do |word|
      if rand < intensity && word.length > 1
        first = word[0]
        "#{first}-#{first}-#{first}-#{word}"
      else
        word
      end
    end.join(' ')
  end
  
  def self.repeat_words(text, intensity: 0.25)
    words = text.split(' ')
    result = []
    words.each do |word|
      result << word
      result << word if rand < intensity  # Random word repetition
      result << word if rand < intensity * 0.5  # Triple sometimes
    end
    result.join(' ')
  end
  
  def self.insert_glitches(text)
    glitches = ['*bzzt*', '*crackle*', '*static*', '*pop*', '*glitch*', 
                '*error*', '*malfunction*', '*distortion*', '*interference*']
    
    words = text.split(' ')
    result = []
    words.each do |word|
      result << glitches.sample if rand < STRANGE_CONFIG[:glitch_probability]
      result << word
    end
    result.join(' ')
  end
  
  def self.phonetic_corruption(text)
    # Replace letters to sound weird
    text.gsub(/s/, 'zh')
        .gsub(/th/, 'zz')
        .gsub(/r/, 'w')
        .gsub(/l/, 'w')
  end
  
  def self.random_pauses(text)
    words = text.split(' ')
    words.map do |word|
      if rand < 0.2
        "#{word} ..."  # Random pause
      else
        word
      end
    end.join(' ')
  end
  
  def self.all_effects(text)
    text = stutter(text, intensity: 0.4)
    text = repeat_words(text, intensity: 0.3)
    text = insert_glitches(text)
    text = random_pauses(text)
    text
  end
end

# ============================================================================
# STRANGE VOICE GENERATOR
# ============================================================================

class StrangeVoice
  def initialize
    @voices = [
      { voice: 'en+croak', pitch: 0, speed: 60 },     # Extremely deep croaky
      { voice: 'en+whisper', pitch: 99, speed: 300 }, # High pitched whisper
      { voice: 'en+m3', pitch: 10, speed: 100 },      # Male deep slow
      { voice: 'en+f4', pitch: 80, speed: 220 },      # Female high fast
      { voice: 'en+croak', pitch: 40, speed: 150 }    # Mid-range croak
    ]
  end
  
  def random_voice
    @voices.sample
  end
  
  def generate(text, output_file)
    voice_config = random_voice
    
    # Use espeak directly instead of espeak-ruby gem
    cmd = "espeak -v #{voice_config[:voice]} -p #{voice_config[:pitch]} -s #{voice_config[:speed]} -w \"#{output_file}\" \"#{text.gsub('"', '\\"')}\" 2>NUL"
    system(cmd)
  end
end

# ============================================================================
# EXTREME LOFI EFFECTS (SOX)
# ============================================================================

class ExtremeLofi
  def self.apply(input_file, output_file, preset: 'maximum_weird')
    sox = STRANGE_CONFIG[:sox] ? 'sox' : 'C:/cygwin64/bin/sox.exe'
    
    effects = case preset
    when 'maximum_weird'
      # Extreme bitcrush + distortion + reverb + pitch warping
      [
        'highpass 200',           # Remove low frequencies
        'rate -q 5512',           # Downsample to 5.5kHz (extreme lofi)
        'rate 22050',             # Back up (aliasing artifacts)
        'lowpass 2800',           # Aggressive lowpass
        'overdrive 35',           # Heavy distortion
        'reverb 80',              # Massive reverb
        'pitch 50',               # Shift pitch up randomly
        'tremolo 0.5 80',         # Heavy tremolo (warble)
        'echo 0.9 0.9 50 0.4',    # Echo
        'gain -5'                 # Reduce volume
      ]
    
    when 'telephone_hell'
      # Telephone quality but worse
      [
        'highpass 400',
        'lowpass 2400',
        'rate 8000',
        'overdrive 50',
        'reverb 60',
        'tremolo 1.0 40',
        'gain -3'
      ]
    
    when 'underwater'
      # Muffled underwater sound
      [
        'lowpass 800',
        'reverb 90',
        'echo 0.8 0.9 200 0.3',
        'pitch -200',
        'tremolo 0.2 60',
        'gain -4'
      ]
    
    when 'nightmare'
      # Horror/nightmare voice
      [
        'pitch -300',
        'reverb 95',
        'echo 0.9 0.88 80 0.5',
        'tremolo 0.1 90',
        'overdrive 20',
        'phaser 0.8 0.74 3 0.4 0.5',
        'gain -6'
      ]
    
    when 'robot_broken'
      # Broken robot/cyborg
      [
        'rate -q 8000',
        'rate 22050',
        'overdrive 60',
        'reverb 40',
        'pitch 100',
        'tremolo 10.0 30',
        'flanger',
        'gain -4'
      ]
    
    when 'vinyl_destroyed'
      # Destroyed vinyl record
      [
        'highpass 150',
        'lowpass 4000',
        'rate -q 11025',
        'rate 22050',
        'overdrive 25',
        'reverb 50',
        'tremolo 0.05 20',
        'gain -3'
      ]
    
    when 'cassette_melted'
      # Melted cassette tape
      [
        'highpass 80',
        'lowpass 3500',
        'pitch -50',
        'bend 0.3,2.0,3.0',  # Pitch warping
        'overdrive 15',
        'tremolo 0.2 40',
        'reverb 30',
        'gain -2'
      ]
    end
    
    # Execute sox with effects
    cmd = "#{sox} \"#{input_file}\" \"#{output_file}\" #{effects.join(' ')} 2>NUL"
    system(cmd)
  end
  
  def self.apply_streaming(input_file, preset: 'maximum_weird')
    sox = STRANGE_CONFIG[:sox] ? 'sox' : 'C:/cygwin64/bin/sox.exe'
    
    effects = case preset
    when 'maximum_weird'
      'highpass 200 rate -q 5512 rate 22050 lowpass 2800 overdrive 35 reverb 80 pitch 50 tremolo 0.5 80 echo 0.9 0.9 50 0.4 gain -5'
    when 'telephone_hell'
      'highpass 400 lowpass 2400 rate 8000 overdrive 50 reverb 60 tremolo 1.0 40 gain -3'
    when 'underwater'
      'lowpass 800 reverb 90 echo 0.8 0.9 200 0.3 pitch -200 tremolo 0.2 60 gain -4'
    when 'nightmare'
      'pitch -300 reverb 95 echo 0.9 0.88 80 0.5 tremolo 0.1 90 overdrive 20 phaser 0.8 0.74 3 0.4 0.5 gain -6'
    when 'robot_broken'
      'rate -q 8000 rate 22050 overdrive 60 reverb 40 pitch 100 tremolo 10.0 30 flanger gain -4'
    when 'vinyl_destroyed'
      'highpass 150 lowpass 4000 rate -q 11025 rate 22050 overdrive 25 reverb 50 tremolo 0.05 20 gain -3'
    when 'cassette_melted'
      'highpass 80 lowpass 3500 pitch -50 overdrive 15 tremolo 0.2 40 reverb 30 gain -2'
    end
    
    # Apply effects to a new file
    output_file = input_file.gsub('.wav', '_processed.wav')
    cmd = "#{sox} \"#{input_file}\" \"#{output_file}\" #{effects} 2>NUL"
    system(cmd)
    
    # Play with PowerShell SoundPlayer
    if File.exist?(output_file)
      ps_cmd = <<~PS
        Add-Type -AssemblyName System.Windows.Forms
        $player = New-Object System.Media.SoundPlayer("#{output_file.gsub('/', '\\')}")
        $player.PlaySync()
      PS
      
      system("powershell.exe", "-Command", ps_cmd)
      File.delete(output_file) if File.exist?(output_file)
    end
  end
end

# ============================================================================
# MAIN INTERFACE
# ============================================================================

class StrangeTTS
  def initialize
    @voice_generator = StrangeVoice.new
    
    puts "🎙️  STRANGE VOICE SYSTEM v1.0"
    puts "  espeak: #{STRANGE_CONFIG[:espeak] ? '✓' : '✗'}"
    puts "  sox: #{STRANGE_CONFIG[:sox] ? '✓' : '✗'}"
    puts ""
  end
  
  def speak(text, preset: 'maximum_weird')
    # Step 1: Corrupt the text
    corrupted_text = TextCorruptor.all_effects(text)
    puts "[CORRUPTED] #{corrupted_text}"
    
    # Step 2: Generate weird voice
    temp_wav = "#{STRANGE_CONFIG[:cache_dir]}/temp_#{Time.now.to_i}.wav"
    @voice_generator.generate(corrupted_text, temp_wav)
    
    # Step 3: Apply extreme lofi effects
    if STRANGE_CONFIG[:sox]
      puts "[EFFECTS] Applying #{preset}..."
      ExtremeLofi.apply_streaming(temp_wav, preset: preset)
      File.delete(temp_wav) if File.exist?(temp_wav)
    else
      puts "[NO SOX] Playing without effects (install sox for full weirdness)"
      system("start /min \"\" \"#{temp_wav}\"")
      sleep 3
      File.delete(temp_wav) if File.exist?(temp_wav)
    end
  end
  
  def demo
    presets = ['maximum_weird', 'telephone_hell', 'underwater', 'nightmare', 
               'robot_broken', 'vinyl_destroyed', 'cassette_melted']
    
    puts "\n=== STRANGE VOICE DEMO ==="
    puts "Testing all presets with corrupted text...\n"
    
    presets.each_with_index do |preset, i|
      puts "\n[#{i+1}/#{presets.length}] #{preset.upcase}"
      speak("Testing strange voice with preset #{preset}", preset: preset)
      sleep 1
    end
    
    puts "\n✓ Demo complete"
  end
end

# ============================================================================
# CLI
# ============================================================================

if __FILE__ == $0
  tts = StrangeTTS.new
  
  command = ARGV[0]
  
  case command
  when 'say', nil
    text = ARGV[1..-1].join(' ')
    text = "Hello from the strange voice system" if text.empty?
    tts.speak(text, preset: 'maximum_weird')
  
  when 'preset'
    preset = ARGV[1] || 'maximum_weird'
    text = ARGV[2..-1].join(' ')
    text = "Testing preset #{preset}" if text.empty?
    tts.speak(text, preset: preset)
  
  when 'demo'
    tts.demo
  
  else
    puts "Strange Voice System - Maximum Weirdness TTS"
    puts ""
    puts "Usage:"
    puts "  ruby strange_voice.rb say <text>"
    puts "  ruby strange_voice.rb preset <preset_name> <text>"
    puts "  ruby strange_voice.rb demo"
    puts ""
    puts "Presets:"
    puts "  maximum_weird    - Extreme bitcrush, distortion, reverb, tremolo"
    puts "  telephone_hell   - Bad telephone but worse"
    puts "  underwater       - Muffled deep underwater sound"
    puts "  nightmare        - Horror/nightmare voice (-300 pitch)"
    puts "  robot_broken     - Malfunctioning robot/cyborg"
    puts "  vinyl_destroyed  - Destroyed vinyl record"
    puts "  cassette_melted  - Melted cassette tape"
    puts ""
    puts "Text corruption includes:"
    puts "  - Random stuttering (40% intensity)"
    puts "  - Word repetition (30% intensity)"
    puts "  - Glitch sounds (*bzzt*, *crackle*, *static*)"
    puts "  - Random pauses"
    puts "  - Phonetic corruption (s→zh, th→zz, r→w)"
  end
end
