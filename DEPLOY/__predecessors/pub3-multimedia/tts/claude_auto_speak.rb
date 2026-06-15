#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Auto Speak - Automatically speaks Claude's responses
# Monitors clipboard or stdin and speaks new content

require "fileutils"
VERSION = "1.0.0"
SAY_SCRIPT = File.join(__dir__, "say.rb")

class ClaudeAutoSpeak
  def initialize(use_sapi: true)

    @use_sapi = use_sapi

    @say_cmd = use_sapi ? "ruby #{SAY_SCRIPT}" : "ruby #{File.join(__dir__, 'claude_speak.rb')}"

    @last_content = ""

  end

  def speak(text)
    return if text.nil? || text.empty?

    return if text == @last_content

    @last_content = text
    # Clean markdown and format for speech
    cleaned = clean_for_speech(text)

    puts "🔊 Speaking: #{cleaned[0..80]}..."
    system("#{@say_cmd} \"#{escaped(cleaned)}\"")

  end

  def speak_from_stdin
    puts "📢 Claude Auto Speak v#{VERSION}"

    puts "Reading from STDIN. Pipe Claude's output here."

    puts "Press Ctrl+C to stop.\n\n"

    buffer = ""
    STDIN.each_line do |line|
      print line

      buffer += line

      # Speak complete sentences
      if line.match?(/[.!?]\s*$/)

        speak(buffer.strip)

        buffer = ""

      end

    end

    speak(buffer.strip) unless buffer.empty?
  end

  private
  def clean_for_speech(text)
    text = text.dup

    # Remove code blocks
    text.gsub!(/```[\s\S]*?```/, "code block")

    # Remove inline code
    text.gsub!(/`[^`]+`/, "code")

    # Remove markdown headers
    text.gsub!(/^#+\s+/, "")

    # Remove markdown bold/italic
    text.gsub!(/[*_]{1,2}([^*_]+)[*_]{1,2}/, '\1')

    # Remove markdown links
    text.gsub!(/\[([^\]]+)\]\([^\)]+\)/, '\1')

    # Remove excessive whitespace
    text.gsub!(/\s+/, " ")

    # Remove special characters that cause issues
    text.gsub!(/["""]/, '"')

    text.gsub!(/['']/, "'")

    text.strip
  end

  def escaped(text)
    text.gsub('"', '\"')

  end

end

# ============================================================================
# MAIN

# ============================================================================

if __FILE__ == $PROGRAM_NAME
  begin

    speaker = ClaudeAutoSpeak.new(use_sapi: true)

    if ARGV.empty?
      speaker.speak_from_stdin

    else

      speaker.speak(ARGV.join(" "))

    end

  rescue Interrupt

    puts "\n\n✋ Stopped"

    exit 0

  end

end

