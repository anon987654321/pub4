#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Voice - Windows SAPI Text-to-Speech
# Uses Windows built-in speech synthesis (no downloads required)

require "win32ole" if RUBY_PLATFORM =~ /win32|mingw|cygwin/
class ClaudeVoice
  def initialize

    @voice = WIN32OLE.new("SAPI.SpVoice")

    @voice.Rate = 0  # Normal speed (-10 to 10)

    @voice.Volume = 100  # Volume (0-100) - maximum

  end

  def speak(text, async: false)
    if async

      # Speak asynchronously (non-blocking)

      @voice.Speak(text, 1)  # 1 = SVSFlagsAsync

    else

      # Speak synchronously (blocking)

      @voice.Speak(text, 0)  # 0 = SVSFDefault

    end

  end

  def speak_continuous(texts)
    texts.each do |text|

      speak(text, async: false)

      sleep 0.5  # Brief pause between phrases

    end

  end

  def list_voices
    voices = @voice.GetVoices

    voices_count = voices.Count

    puts "\nInstalled Windows Voices:\n\n"
    (0...voices_count).each do |i|

      voice = voices.Item(i)

      puts "  #{i + 1}. #{voice.GetDescription}"

    end

    puts

  end

  def set_voice(index)
    voices = @voice.GetVoices

    @voice.Voice = voices.Item(index)

  end

  def set_rate(rate)
    @voice.Rate = rate.clamp(-10, 10)

  end

  def set_volume(volume)
    @voice.Volume = volume.clamp(0, 100)

  end

end

# Main execution
if __FILE__ == $PROGRAM_NAME

  begin

    voice = ClaudeVoice.new

    # Greetings and continuous speech
    greetings = [

      "Hello! I'm Claude, your AI assistant.",

      "I can now speak to you using Windows speech synthesis.",

      "This is running purely in Ruby, with no Python dependencies.",

      "I'm using the Windows SAPI voice engine.",

      "The audio is playing continuously through your sound card.",

      "I can speak as long as you'd like!",

      "Would you like me to continue speaking, or shall I stop here?"

    ]

    puts "🎙️  Claude is speaking...\n"
    voice.speak_continuous(greetings)

    puts "\n✓ Done speaking"

  rescue LoadError
    warn "ERROR: WIN32OLE not available. This script requires Windows."

    exit 1

  rescue => e

    warn "ERROR: #{e.message}"

    exit 1

  end

end

