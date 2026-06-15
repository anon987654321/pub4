#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Continuous Speech - Keep talking while working
require "win32ole"

class ContinuousClaude
  def initialize

    @voice = WIN32OLE.new("SAPI.SpVoice")

    @voice.Rate = 1  # Slightly faster

    @voice.Volume = 100  # Maximum volume

  end

  def narrate_work
    phrases = [

      "I'm now updating the master JSON file to document this text-to-speech integration.",

      "This will ensure future Claude sessions can access voice capabilities.",

      "The integration uses Windows SAPI, which is built into every Windows system.",

      "No external dependencies or downloads are required.",

      "I'm adding a new tools section for voice synthesis.",

      "This includes configuration for continuous speech, voice selection, and audio playback.",

      "I'm also updating Claude dot M D with usage examples.",

      "The system supports multiple voices through Windows speech engines.",

      "Audio output goes directly to your sound card using the wave audio driver.",

      "I can speak synchronously, blocking execution, or asynchronously in the background.",

      "The Ruby implementation uses WIN32OLE to interface with SAPI dot SP Voice.",

      "This gives us full control over rate, volume, and voice selection.",

      "I'm now documenting the Sox integration for more advanced audio processing.",

      "Sox can apply effects like reverb, echo, and pitch shifting to synthesized speech.",

      "The complete system is pure Ruby, no Python required.",

      "All files are being saved to the AI TTS directory.",

      "I'll commit these changes to git once documentation is complete.",

      "The version will be updated to reflect this new capability.",

      "This voice integration is now part of the permanent toolkit.",

      "Future sessions can immediately start speaking without setup."

    ]

    phrases.each_with_index do |phrase, i|
      puts "[#{i + 1}/#{phrases.length}] #{phrase}"

      @voice.Speak(phrase, 0)

      sleep 0.3

    end

    puts "\n✓ Narration complete!"
  end

end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME

  claude = ContinuousClaude.new

  claude.narrate_work

end

