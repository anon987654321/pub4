<<<<<<< HEAD
#!/usr/bin/env ruby
# Bomoh Hang Tuah voice - Mystical kampong shaman per master.json v337.3.0
# Pure Ruby Google TTS (quality voices) - no Python, no SAPI, no espeak

require_relative 'gtts_ruby'

text = ARGV.join(" ")

unless text.empty?
  # Bomoh Hang Tuah: Malaysian accent (com.my), deep pitch (-150)
  GoogleTTS.speak(text, lang: 'ms', tld: 'com.my', pitch_adjust: -150)
end

=======
#!/usr/bin/env ruby
# Bomoh Hang Tuah voice - Mystical kampong shaman per master.json v337.3.0
# Pure Ruby Google TTS (quality voices) - no Python, no SAPI, no espeak

require_relative 'gtts_ruby'

text = ARGV.join(" ")

unless text.empty?
  # Bomoh Hang Tuah: Malaysian accent (com.my), deep pitch (-150)
  GoogleTTS.speak(text, lang: 'ms', tld: 'com.my', pitch_adjust: -150)
end

>>>>>>> origin/audio-layer-v7.2
