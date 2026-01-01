#!/usr/bin/env ruby
# URGENT: Full beat assembly for tonight
# Using: 808 drums (GoldBaby) + R-Mårdalen sample + Dilla swing

require_relative 'dilla'

puts "🔥 URGENT BEAT ASSEMBLY - Dilla Style"
puts "="*50

# Initialize
dilla = SOSDilla.new

# Generate base Dilla beat
dilla.generate_dilla(style: "donuts", key: "C", bpm: 95)

puts "\n✅ Beat generated! Check #{dilla.output_dir}"
