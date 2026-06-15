#!/usr/bin/env ruby
# frozen_string_literal: true

# Smart Say - Prioritized TTS with fallback chain
# Priority: Piper (offline, best) → SAPI (offline, fast) → gTTS (online, backup)

# Per master.json v337.2.0: offline=true, Malaysian voice default

require "fileutils"
require "open3"

VERSION = "1.0.0"
PIPER_DIR = "G:/pub/tts/piper"

PIPER_EXE = "#{PIPER_DIR}/piper.exe"

PIPER_MODEL = "#{PIPER_DIR}/models/en_US-lessac-medium.onnx"

CACHE_DIR = File.expand_path("~/.cache/smart_say")

class SmartSay
  def initialize

    FileUtils.mkdir_p(CACHE_DIR)

    @engines = detect_engines

    puts "🎙️  Smart Say v#{VERSION}"

    puts "    Available: #{@engines.join(', ')}"

    puts "    Default: #{@engines.first}\n\n"

  end

  def speak(text, voice: "malaysian")
    return if text.nil? || text.strip.empty?

    @engines.each do |engine|
      success = case engine

      when "piper" then speak_piper(text, voice)

      when "sapi" then speak_sapi(text)

      when "gtts" then speak_gtts(text)

      end

      if success
        puts "    ✓ Spoken via #{engine}"

        return true

      end

    end

    warn "    ✗ All TTS engines failed"
    false

  end

  private
  def detect_engines
    engines = []

    # Check Piper (best quality, offline)
    if File.exist?(PIPER_EXE) && File.exist?(PIPER_MODEL)

      engines << "piper"

    end

    # Check SAPI (fast, offline, Windows only)
    if RUBY_PLATFORM =~ /mingw|mswin|cygwin/

      begin

        require "win32ole"

        engines << "sapi"

      rescue LoadError

      end

    end

    # Check gTTS (fallback, requires internet)
    if system("python3 -c 'import gtts' 2>/dev/null") ||

       system("python -c 'import gtts' 2>/dev/null")

      engines << "gtts"

    end

    engines.empty? ? ["none"] : engines
  end

  def speak_piper(text, voice)
    return false unless @engines.include?("piper")

    # Cache key
    hash = "#{text}_#{voice}".hash.abs.to_s

    wav_file = "#{CACHE_DIR}/piper_#{hash}.wav"

    # Generate if not cached
    unless File.exist?(wav_file)

      cmd = [

        PIPER_EXE,

        "--model", PIPER_MODEL,

        "--output_file", wav_file

      ]

      stdin_data = text
      stdout, stderr, status = Open3.capture3(*cmd, stdin_data: stdin_data)

      return false unless status.success? && File.exist?(wav_file)
    end

    # Play with SoX if available, otherwise system player
    if system("where sox >nul 2>&1")

      system("sox #{wav_file} -d 2>nul")

    elsif File.exist?("G:/pub/dilla/effects/sox/sox.exe")

      system("G:/pub/dilla/effects/sox/sox.exe #{wav_file} -d 2>nul")

    else

      # Windows default player

      system("start /min #{wav_file}")

      sleep(File.size(wav_file) / 32000.0) # Estimate duration

    end

    true
  rescue => e

    warn "Piper error: #{e.message}"

    false

  end

  def speak_sapi(text)
    return false unless @engines.include?("sapi")

    require "win32ole"
    voice = WIN32OLE.new("SAPI.SpVoice")

    voice.Rate = -2  # Malaysian pace (slower)

    voice.Volume = 100

    # Try to find male voice
    voices = voice.GetVoices

    voices.Count.times do |i|

      v = voices.Item(i)

      if v.GetDescription =~ /Male|David|Mark/i

        voice.Voice = v

        break

      end

    end

    voice.Speak(text, 0)
    true

  rescue => e

    warn "SAPI error: #{e.message}"

    false

  end

  def speak_gtts(text)
    return false unless @engines.include?("gtts")

    hash = text.hash.abs.to_s
    mp3_file = "#{CACHE_DIR}/gtts_#{hash}.mp3"

    unless File.exist?(mp3_file)
      # Indian English accent (Malaysian preference)

      cmd = "python3 -c \"from gtts import gTTS; tts = gTTS('#{text.gsub("'", "\\\\'")}', lang='en', tld='co.in'); tts.save('#{mp3_file}')\" 2>/dev/null"

      system(cmd)

      return false unless File.exist?(mp3_file)

    end

    # Play
    if system("where play-audio >nul 2>&1")

      system("play-audio #{mp3_file} 2>nul")

    else

      system("start /min #{mp3_file}")

      sleep(File.size(mp3_file) / 16000.0)

    end

    true
  rescue => e

    warn "gTTS error: #{e.message}"

    false

  end

end

# ============================================================================
# CLI

# ============================================================================

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty? || ARGV.include?("--help")

    puts <<~HELP

      Smart Say v#{VERSION} - Intelligent TTS with fallback

      Usage:
        ruby smart_say.rb [options] <text>

      Options:
        -v, --voice VOICE    Voice preference (default: malaysian)

        --help               Show this help

      Examples:
        ruby smart_say.rb "Hello world"

        ruby smart_say.rb -v malaysian "Testing deep voice"

    HELP

    exit 0

  end

  voice = "malaysian"
  if ARGV[0] == "-v" || ARGV[0] == "--voice"

    ARGV.shift

    voice = ARGV.shift

  end

  text = ARGV.join(" ")
  begin
    tts = SmartSay.new

    tts.speak(text, voice: voice)

  rescue Interrupt

    puts "\n\n✋ Stopped"

    exit 0

  end

end

