#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true

# Thin wrapper — dossier + deep analysis lives in MASTER/tools/dilla/dilla.rb
require_relative "../dilla/dilla"

if $PROGRAM_NAME == __FILE__
  path = RadioBergenStudy.write_dossiers!
  data = RadioBergenStudy.dossiers!
  puts "wrote #{path}"
  puts "measured #{data.dig('meta', 'measured_local')}/#{data.dig('meta', 'tracks')} tracks"
end
