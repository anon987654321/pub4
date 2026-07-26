#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

# Thin wrapper — study logic lives in studio/dilla/engine.rb (RadioBergenStudy).
require_relative "../dilla/engine"

if $PROGRAM_NAME == __FILE__
  json = ARGV.include?("--json")
  audio_root = nil
  if (idx = ARGV.index("--audio-root"))
    audio_root = ARGV[idx + 1]
  end
  data = RadioBergenStudy.study!(audio_root:)
  if json
    require "json"
    puts JSON.pretty_generate(data)
  else
    path = RadioBergenStudy.write!(audio_root:)
    puts "wrote #{path} (#{data.dig('meta', 'track_count')} tracks)"
    puts "stream weights: #{data['stream_rotation_weights'].keys.first(5).join(', ')}…"
  end
end
