#!/usr/bin/env ruby
# frozen_string_literal: true

# demo2.wav — industrial / classic techno from the catalogue rows that
# already sit on the floor: four_floor, detroit, hate_rumble.
# The operator prefers this take to demo.wav.
Dir.chdir(__dir__)
ENV["DILLA_OVERWRITE"] = "1"
require_relative "dilla"

dest = ENV["DEMO2_OUT"] || File.join(ROOT, "demo2.wav")
names = %w[four_floor detroit hate_rumble]
scratch = File.join(ROOT, "scratch", "demo2")
FileUtils.mkdir_p(scratch)
parts = names.each_with_index.map do |name, i|
  path = File.join(scratch, format("%02d_%s.wav", i, name))
  existing = File.join(ROOT, "scratch", "pieces", format("%02d_%s.wav", i + 2, name))
  if File.file?(existing)
    FileUtils.cp(existing, path)
  else
    Bed.spawn_piece!(name, path, (ENV["RENDER_SEED"] || Time.now.to_i).to_i + i, seconds: 16)
  end
  path
end
Bed.join_catalogue(parts, dest, 0.5)
Bed.grit_catalogue!(dest)
mp3 = demo_encode_mp3(dest)
warn "ok: #{dest}"
warn "ok: #{mp3}" if mp3
