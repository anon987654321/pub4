#!/usr/bin/env ruby
# frozen_string_literal: true

# Simplified Dilla beat generator using pure Ruby (no external audio tools)
# Based on mb-sound principles: https://github.com/mike-bourgeous/mb-sound

class DillaSimple
  VERSION = "2.0.0"
  
  def self.generate(style: "donuts_classic", key: "C", bpm: 90)
    puts "🎵 Generating #{style} beat in #{key} at #{bpm}BPM (simplified)"
    
    # Generate simple sine wave beat pattern (proof of concept)
    sample_rate = 44100
    duration = 4.0 # 4 seconds
    samples = (sample_rate * duration).to_i
    
    # Kick drum pattern (on beats 1 and 3)
    kick_freq = 60 # Hz
    kick_pattern = Array.new(samples) do |i|
      time = i.to_f / sample_rate
      beat_time = (time * bpm / 60.0) % 4.0
      
      if beat_time < 0.1 || (beat_time >= 2.0 && beat_time < 2.1)
        envelope = Math.exp(-50 * (beat_time % 2.0))
        Math.sin(2 * Math::PI * kick_freq * time) * envelope * 0.8
      else
        0.0
      end
    end
    
    # Hi-hat pattern (8th notes with swing)
    hat_pattern = Array.new(samples) do |i|
      time = i.to_f / sample_rate
      beat_time = (time * bpm / 60.0) % 4.0
      eighth_note = (beat_time * 2).to_i
      
      # Add swing (delay every other hit)
      swing = eighth_note.odd? ? 0.12 : 0.0
      adjusted_time = beat_time + swing
      
      if (adjusted_time * 2) % 1.0 < 0.02
        # White noise simulation with high-pass sine
        (rand - 0.5) * 0.3
      else
        0.0
      end
    end
    
    # Mix kick and hats
    mixed = kick_pattern.zip(hat_pattern).map { |k, h| k + h }
    
    # Normalize
    max_val = mixed.map(&:abs).max
    mixed.map! { |v| v / max_val * 0.9 } if max_val > 0
    
    # Write 16-bit WAV
    output_file = "dilla_simple_#{style}_#{key}_#{bpm}bpm.wav"
    write_wav(output_file, mixed, sample_rate)
    
    puts "✓ Generated #{output_file}"
    puts "  Duration: #{duration}s"
    puts "  Sample rate: #{sample_rate}Hz"
    puts "  Samples: #{samples}"
    
    output_file
  end
  
  def self.write_wav(filename, samples, sample_rate)
    # Simple WAV file writer (16-bit mono PCM)
    num_samples = samples.length
    byte_rate = sample_rate * 2 # 16-bit = 2 bytes
    
    File.open(filename, "wb") do |f|
      # RIFF header
      f.write("RIFF")
      f.write([36 + num_samples * 2].pack("V")) # File size - 8
      f.write("WAVE")
      
      # fmt chunk
      f.write("fmt ")
      f.write([16].pack("V")) # Chunk size
      f.write([1].pack("v"))  # Audio format (1 = PCM)
      f.write([1].pack("v"))  # Num channels (1 = mono)
      f.write([sample_rate].pack("V"))
      f.write([byte_rate].pack("V"))
      f.write([2].pack("v"))  # Block align
      f.write([16].pack("v")) # Bits per sample
      
      # data chunk
      f.write("data")
      f.write([num_samples * 2].pack("V"))
      
      # Sample data (16-bit signed integers)
      samples.each do |sample|
        int_sample = (sample * 32767).round.clamp(-32768, 32767)
        f.write([int_sample].pack("s"))
      end
    end
  end
end

# CLI interface
if __FILE__ == $0
  style = ARGV[0] || "donuts_classic"
  key = ARGV[1] || "C"
  bpm = (ARGV[2] || 90).to_i
  
  DillaSimple.generate(style: style, key: key, bpm: bpm)
end
