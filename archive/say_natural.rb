#!/usr/bin/env ruby
# say_natural.rb - Natural voice with optional lofi deterioration
# Edge-TTS + FFmpeg effects for vinyl, bitcrush, etc.

require 'fileutils'

CACHE_DIR = 'G:/pub/multimedia/tts/cache'
FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)

# Natural voices
VOICES = {
  aria: 'en-US-AriaNeural',
  guy: 'en-US-GuyNeural',
  jenny: 'en-US-JennyNeural',
  christopher: 'en-US-ChristopherNeural',
  eric: 'en-US-EricNeural',
  michelle: 'en-US-MichelleNeural'
}

# Lofi deterioration presets
LOFI_PRESETS = {
  clean: {
    desc: "Clean natural voice (no effects)",
    ffmpeg: nil
  },
  
  vinyl: {
    desc: "Worn vinyl record - crackle, warmth, slow wobble",
    ffmpeg: "highpass=f=150,lowpass=f=8000,vibrato=f=0.1:d=0.3,tremolo=f=0.05:d=0.15,volume=0.9"
  },
  
  cassette: {
    desc: "Old cassette tape - warble, hiss, flutter",
    ffmpeg: "highpass=f=100,lowpass=f=7000,vibrato=f=0.2:d=0.4,tremolo=f=0.1:d=0.2,equalizer=f=4000:t=q:w=1:g=-2,volume=0.88"
  },
  
  telephone: {
    desc: "Phone quality - narrow bandwidth 300-3400Hz",
    ffmpeg: "highpass=f=300,lowpass=f=3400,volume=1.0"
  },
  
  radio: {
    desc: "AM radio - compressed, band-limited, slight distortion",
    ffmpeg: "highpass=f=400,lowpass=f=4500,compand=0.3|0.3:1|1:-90/-60|-60/-40|-40/-30|-20/-20:6:0:-90:0.2,volume=0.85"
  },
  
  bitcrush_light: {
    desc: "Light bitcrushing - 12-bit warmth, subtle aliasing",
    ffmpeg: "acrusher=bits=12:samples=1:mix=0.6:mode=log:aa=1,highpass=f=80,lowpass=f=8000,volume=0.9"
  },
  
  bitcrush_heavy: {
    desc: "Heavy bitcrushing - 8-bit, aggressive aliasing",
    ffmpeg: "acrusher=bits=8:samples=2:mix=0.85:mode=log:aa=0,highpass=f=150,lowpass=f=5000,volume=0.85"
  },
  
  lofi: {
    desc: "Classic lofi - bitcrush + tape warmth + slight distortion",
    ffmpeg: "acrusher=bits=10:samples=1:mix=0.7:mode=log:aa=1,highpass=f=120,lowpass=f=6500,vibrato=f=0.15:d=0.25,volume=0.88"
  },
  
  underwater: {
    desc: "Underwater/muffled - heavy lowpass, reverb feel",
    ffmpeg: "lowpass=f=1200,highpass=f=100,equalizer=f=500:t=q:w=1.5:g=3,volume=0.8"
  },
  
  megaphone: {
    desc: "Megaphone/loudspeaker - mid-focused, slight distortion",
    ffmpeg: "highpass=f=600,lowpass=f=3500,equalizer=f=1500:t=q:w=2:g=6,volume=1.1"
  },
  
  gramophone: {
    desc: "1920s gramophone - extreme band-limiting, crackle simulation",
    ffmpeg: "highpass=f=500,lowpass=f=2800,vibrato=f=0.08:d=0.4,tremolo=f=0.03:d=0.25,equalizer=f=1000:t=q:w=3:g=-4,volume=0.75"
  },
  
  vhs: {
    desc: "VHS tape degradation - warble, muffled, tracking errors",
    ffmpeg: "highpass=f=120,lowpass=f=6000,vibrato=f=0.3:d=0.5,tremolo=f=0.2:d=0.3,equalizer=f=3000:t=q:w=1:g=-3,volume=0.82"
  },
  
  robot_clean: {
    desc: "Clean robot voice - slight processing, digital feel",
    ffmpeg: "highpass=f=200,equalizer=f=2000:t=q:w=1:g=-2,equalizer=f=6000:t=q:w=1:g=3,volume=0.95"
  },
  
  robot_broken: {
    desc: "Broken robot - bitcrush + distortion + glitchy tremolo",
    ffmpeg: "acrusher=bits=8:samples=2:mix=0.9:mode=lin,highpass=f=300,tremolo=f=8:d=0.4,volume=0.8"
  },
  
  blown_speaker: {
    desc: "Blown speaker - distortion, rattling, frequency damage",
    ffmpeg: "highpass=f=200,lowpass=f=4000,compand=0.1|0.1:1|1:-90/-60|-60/-20|-20/-10|-10/-5:6:0:-90:0.1,tremolo=f=15:d=0.2,volume=1.0"
  },
  
  cave: {
    desc: "Cave reverb - echo, spacious, muffled",
    ffmpeg: "aecho=1.0:0.7:60:0.5,aecho=1.0:0.6:100:0.4,lowpass=f=5000,volume=0.85"
  }
}

def speak_natural(text, voice: :aria, preset: :clean)
  voice_name = VOICES[voice] || VOICES[:aria]
  
  base_file = "#{CACHE_DIR}/natural_#{Time.now.to_i}.mp3"
  
  puts "[Natural Voice] #{voice} - #{LOFI_PRESETS[preset][:desc]}"
  puts "  Text: #{text}"
  
  # Generate with Edge-TTS
  cmd = "py -m edge_tts --voice #{voice_name} --text \"#{text.gsub('"', '\\"')}\" --write-media \"#{base_file}\" 2>NUL"
  system(cmd)
  
  if !File.exist?(base_file)
    puts "ERROR: Failed to generate audio"
    return
  end
  
  # Apply effects if not clean
  if preset != :clean && LOFI_PRESETS[preset][:ffmpeg]
    processed_file = base_file.gsub('.mp3', '_fx.mp3')
    effects = LOFI_PRESETS[preset][:ffmpeg]
    
    puts "  Applying: #{preset}"
    
    ffmpeg_cmd = "ffmpeg -i \"#{base_file}\" -af \"#{effects}\" -y \"#{processed_file}\" 2>NUL"
    system(ffmpeg_cmd)
    
    File.delete(base_file) if File.exist?(base_file)
    playback_file = processed_file
  else
    playback_file = base_file
  end
  
  # Play
  if File.exist?(playback_file)
    ps = <<~PS
      Add-Type -AssemblyName presentationCore
      $player = New-Object System.Windows.Media.MediaPlayer
      $player.Open([Uri]::new("#{playback_file.gsub('/', '\\')}"))
      $player.Play()
      Start-Sleep 7
      $player.Stop()
      $player.Close()
    PS
    
    system("powershell.exe", "-Command", ps)
    File.delete(playback_file) if File.exist?(playback_file)
  end
end

# CLI
if __FILE__ == $0
  require 'optparse'
  
  options = {
    voice: :aria,
    preset: :clean
  }
  
  OptionParser.new do |opts|
    opts.banner = "Natural Voice TTS with Lofi Effects\n\nUsage: ruby say_natural.rb [options] \"text\""
    
    opts.on("-v", "--voice VOICE", "Voice: aria, guy, jenny, christopher, eric, michelle") do |v|
      options[:voice] = v.to_sym
    end
    
    opts.on("-p", "--preset PRESET", "Effect preset (see --list)") do |p|
      options[:preset] = p.to_sym
    end
    
    opts.on("-l", "--list", "List all available presets") do
      puts "\nAvailable Lofi Presets:\n\n"
      LOFI_PRESETS.each do |name, info|
        puts "  #{name.to_s.ljust(18)} - #{info[:desc]}"
      end
      puts "\nVoices: #{VOICES.keys.join(', ')}"
      exit
    end
  end.parse!
  
  text = ARGV.join(' ')
  
  if text.empty?
    puts "Usage: ruby say_natural.rb [options] \"your text\""
    puts "       ruby say_natural.rb --list           (show all presets)"
    puts ""
    puts "Examples:"
    puts "  ruby say_natural.rb \"Hello world\""
    puts "  ruby say_natural.rb -p vinyl \"Testing vinyl sound\""
    puts "  ruby say_natural.rb -p bitcrush_heavy -v guy \"Heavy bitcrushed voice\""
    puts "  ruby say_natural.rb -p telephone \"Phone quality test\""
    exit
  end
  
  speak_natural(text, voice: options[:voice], preset: options[:preset])
end
