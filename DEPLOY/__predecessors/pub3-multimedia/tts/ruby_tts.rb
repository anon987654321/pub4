#!/usr/bin/env ruby
# Pure Ruby TTS using 'tts' gem (Google Translate API)
# No Python dependencies - Ruby only per master.json v337.3.0

require 'tts'
require 'fileutils'
require 'cgi'

# Fix for deprecated URI.escape in newer Ruby
module URI
  def self.escape(str)
    CGI.escape(str)
  end
end

module RubyTTS
  CACHE_DIR = File.expand_path("~/.tts_cache_ruby")
  SOX_PATH = "G:/pub/dilla/effects/sox/sox.exe"

  def self.setup
    FileUtils.mkdir_p(CACHE_DIR)
    check_sox
  end

  def self.check_sox
    unless File.exist?(SOX_PATH)
      warn "⚠️  Sox not found at #{SOX_PATH}"
    end
  end

  def self.speak(text, speed: 1.0, pitch_adjust: 0, accent: 'in')
    setup

    text_hash = "#{text}#{speed}#{pitch_adjust}#{accent}".hash.abs.to_s
    raw_mp3 = "#{CACHE_DIR}/raw_#{text_hash}.mp3"
    processed_wav = "#{CACHE_DIR}/processed_#{text_hash}.wav"

    # Generate MP3 using tts gem (Google Translate)
    unless File.exist?(raw_mp3)
      # tts gem uses .co.in for Indian accent
      lang = case accent
      when 'in' then 'en'
      when 'co.in' then 'en'
      else 'en'
      end

      begin
        text.to_file(lang, raw_mp3)
      rescue => e
        warn "❌ TTS generation failed: #{e.message}"
        return false
      end
    end

    # Apply Sox effects: pitch shift, bass boost, reverb, normalization
    if File.exist?(SOX_PATH) && File.exist?(raw_mp3)
      # Bomoh voice: very deep pitch (-150 semitones = -150/100 = -1.5 octaves = 12.5 semitones down)
      pitch_semitones = (pitch_adjust / 12.0).round(1)
      tempo = speed

      sox_effects = "pitch #{pitch_semitones} bass +5 treble -3 compand 0.3,1 6:-70,-60,-20 -5 -90 0.2 reverb 15 norm -2"

      cmd = "#{SOX_PATH} \"#{raw_mp3}\" \"#{processed_wav}\" #{sox_effects}"

      unless system(cmd)
        warn "⚠️  Sox processing failed, using raw audio"
        processed_wav = raw_mp3
      end
    else
      processed_wav = raw_mp3
    end

    # Play audio (Windows)
    play_audio(processed_wav)
  end

  def self.play_audio(file)
    if File.exist?(file)
      # Windows playback using SoX
      if File.exist?(SOX_PATH)
        system("#{SOX_PATH} \"#{file}\" -t waveaudio -d")
      else
        # Fallback to Windows Media Player
        system("start /min wmplayer \"#{file}\"")
      end
    end
  end
end

# CLI interface
if __FILE__ == $0
  text = ARGV.join(" ")
  unless text.empty?
    RubyTTS.speak(text, speed: 0.85, pitch_adjust: -150, accent: 'in')
  end
end
