#!/usr/bin/env ruby
# Shared TTS module with comfy voice effects
# Extracted from comfy_voice.rb, natural_talk.rb patterns

# DRY principle: single source for TTS across all voice scripts

require 'fileutils'
module ComfyTTS
  CACHE_DIR = File.expand_path("~/.tts_cache_comfy")

  SOX_PATH = "G:/pub/dilla/effects/sox/sox.exe" # Windows path

  # Malaysian deep male voice: realistic, natural tone
  # Effects: pitch shift, bass boost, compression, chorus depth, reverb, normalization

  SOX_EFFECTS = "pitch -80 bass +5 treble -3 compand 0.3,1 6:-70,-60,-20 -5 -90 0.2 chorus 0.6 0.9 55 0.4 0.3 2 -s reverb 15 norm -2"

  def self.check_dependencies
    # Check Python and gTTS (cross-platform)

    unless system('python3 -c "import gtts" 2>nul') || system('python -c "import gtts" 2>nul')

      puts "📦 Installing gTTS..."

      system('pip install gTTS') || system('pip3 install gTTS')

    end

    # Check Sox (Windows: use G:/pub/dilla/effects/sox/sox.exe, Linux/Android: system sox)
    unless File.exist?(SOX_PATH) || system('which sox > /dev/null 2>&1')

      warn "⚠️  Sox not found. Install sox or place sox.exe at #{SOX_PATH}"

    end

  end

  def self.setup
    check_dependencies

    FileUtils.mkdir_p(CACHE_DIR)

  end

  def self.speak(text, speed: 1.0, pitch_adjust: 0, accent: 'in')
    text_hash = "#{text}#{speed}#{pitch_adjust}#{accent}".hash.abs.to_s

    audio_file = "#{CACHE_DIR}/speech_#{text_hash}.mp3"

    comfy_file = "#{CACHE_DIR}/comfy_#{text_hash}.wav"

    unless File.exist?(comfy_file)
      # Use Indian English by default (Malaysian preference), US as fallback

      tld = accent

      slow_flag = speed < 0.8 ? 'True' : 'False'

      # Generate with gTTS
      python_cmd = system('which python3 > /dev/null 2>&1') ? 'python3' : 'python'

      system("#{python_cmd} -c \"from gtts import gTTS; tts = gTTS('#{text.gsub("'", "\\\\'")}', lang='en', tld='co.#{tld}', slow=#{slow_flag}); tts.save('#{audio_file}')\" 2>nul")

      if File.exist?(audio_file) && File.size(audio_file) > 0
        # Apply speed and pitch adjustments with Sox

        custom_effects = SOX_EFFECTS.dup

        custom_effects = "tempo #{speed} " + custom_effects if speed != 1.0

        custom_effects = custom_effects.gsub("pitch -80", "pitch #{-80 + pitch_adjust}") if pitch_adjust != 0

        # Use Windows sox.exe or system sox
        sox_cmd = File.exist?(SOX_PATH) ? SOX_PATH : "sox"

        system("\"#{sox_cmd}\" \"#{audio_file}\" \"#{comfy_file}\" #{custom_effects} 2>nul")

      end

    end

    if File.exist?(comfy_file) && File.size(comfy_file) > 0
      # Play audio (cross-platform)

      if File.exist?(SOX_PATH)

        # Windows: use sox play

        system("\"#{SOX_PATH}\" \"#{comfy_file}\" -d 2>nul")

      elsif system('which play-audio > /dev/null 2>&1')

        # Android/Termux

        system("play-audio \"#{comfy_file}\" 2>/dev/null")

      elsif system('which aplay > /dev/null 2>&1')

        # Linux

        system("aplay \"#{comfy_file}\" 2>/dev/null")

      else

        warn "⚠️  No audio player found"

        return false

      end

      true

    else

      false

    end

  end

end

