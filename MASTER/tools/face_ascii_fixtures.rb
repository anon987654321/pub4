# frozen_string_literal: true

# Writes test/fixtures/face_ascii_frames.json: the exact frames the Ruby ASCII
# face draws for fixed (rows, cols, state, t, seed), with the vertices' digest and
# the Look each came from. The Ruby test asserts them; the web face's port
# asserts the same file under node (cell differences up to "tolerance" are
# allowed, since libm's sin and cos may differ in the last bit between
# runtimes). Run after any change to data/tokens.yml face_interface.ascii or to
# the renderer, and commit the result: `ruby tools/face_ascii_fixtures.rb`.
#
# `ruby tools/face_ascii_fixtures.rb ink [font-file] [points]` writes nothing: it
# prints the ink density of every printable ASCII glyph in a monospace face (the
# share of one character cell the glyph blackens, drawn black on white in a cell
# of the face's own advance and line height, read back as the cell's mean) and
# the ramp in data/tokens.yml (face_interface.ascii.chars and .ink) is chosen
# from it. Needs ImageMagick (`magick`) and a monospace font file, by default
# macOS Menlo (advance 0.602 em, line height 1.17 em).

require "json"
require_relative "../lib/master"

include Master::CLI

def ink_table(font, points)
  width = (points * 0.602).round
  height = (points * 1.17).round
  table = (33..126).to_h do |code|
    char = code.chr
    # -annotate reads a backslash as an escape, so a literal one is doubled.
    out, = Master::Io::Exec.capture2("magick", "-size", "#{width}x#{height}", "xc:white", "-font", font, "-pointsize", points.to_s, "-gravity", "center",
                                     "-fill", "black", "-annotate", "0", char == "\\" ? "\\\\" : char, "-format", "%[fx:1-mean]", "info:")
    [char, out.to_f]
  end
  puts "font #{File.basename(font)} at #{points} px, cell #{width}x#{height}"
  table.sort_by { |glyph, density| [density, glyph] }.each { |glyph, density| puts format("%-2s %.4f", glyph, density) }
end

if ARGV.first == "ink"
  ink_table(ARGV[1] || "/System/Library/Fonts/Menlo.ttc", (ARGV[2] || 72).to_i)
  exit
end

CUBE = <<~OBJ
  v -1 -1 -1
  v 1 -1 -1
  v 1 1 -1
  v -1 1 -1
  v -1 -1 1
  v 1 -1 1
  v 1 1 1
  v -1 1 1
  f 1 2 3 4
  f 5 8 7 6
  f 1 5 6 2
  f 2 6 7 3
  f 3 7 8 4
  f 5 1 4 8
OBJ

CASES = [
  ["head front", :head, 28, 64, :idle, 0.0, 1],
  ["head three-quarter", :head, 28, 64, :idle, 2.6, 1],
  ["head profile", :head, 28, 64, :idle, 4.5, 1],
  ["head small", :head, 20, 40, :idle, 1.0, 3],
  ["head speaking", :head, 28, 64, :speaking, 1.35, 1],
  ["head listening", :head, 28, 64, :listening, 0.5, 1],
  ["head blink", :head, 28, 64, :idle, 3.3, 0],
  ["head light orbit", :head, 28, 64, :idle, 8.0, 1],
  ["head close-up", :head, 44, 140, :speaking, 1.9, 2],
  ["cube", :cube, 16, 40, :idle, 2.0, 0],
  ["head mid", :head, 44, 110, :idle, 0.7, 1],
  ["head large", :head, 60, 160, :speaking, 1.35, 1],
  ["head extra large", :head, 100, 240, :idle, 2.6, 2],
].freeze

# Each mask at mix 0, 0.5 and 1.0 on the front, and at 1.0 turned three-quarters.
MASK_CASES = Face::Masks::ORDER.flat_map do |mask|
  [0.0, 0.5, 1.0].map { |mix| ["#{mask} #{mix}", mask, mix, 0.0] } + [["#{mask} 1.0 turned", mask, 1.0, 2.6]]
end.freeze
SESSIONS = ["", "master", "abc", "session-1", "conversation 42", "öéあ", "0", "7"].freeze
MIXES = [[:thinking, 0.0, 0.0, 0.0], [:thinking, 0.6, 0.0, 0.0], [:thinking, 1.2, 0.0, 0.0], [:thinking, 5.0, 0.0, 0.0],
         [:thinking, 0.3, 0.5, 0.25], [:idle, 0.4, 0.0, 1.0], [:speaking, 0.4, 0.0, 0.7], [:idle, 3.0, 1.0, 1.0],
         [:listening, 0.1, 0.0, 0.5]].freeze

def source(kind) = kind == :head ? nil : Face::Mesh.parse(CUBE)

cases = CASES.map do |name, kind, rows, cols, state, t, seed|
  src = source(kind) || Face::Head.for(rows, cols)
  look = Face::Pose.at(state, t, seed)
  ascii = Face::Ascii.new(src, rows, cols, chars: Face::Glyphs::DEFAULT_CHARS, mode: "dark")
  { name:, source: kind == :head ? { kind: "head" } : { kind: "mesh", ref: "cube" }, rows:, cols:, state: state.to_s, t:, seed:,
    look: look.to_h.except(:particles, :mask, :mix), digest: ascii.digest, lines: ascii.render(look, state:).chars.map(&:join) }
end

masks = MASK_CASES.map do |name, mask, mix, t|
  rows = 28
  cols = 64
  look = Face::Pose.at(:idle, t, 1)
  ascii = Face::Ascii.new(Face::Masks.source(Face::Head.for(rows, cols), mask, mix), rows, cols, chars: Face::Glyphs::DEFAULT_CHARS, mode: "dark")
  { name:, source: { kind: "head" }, mask:, mix:, rows:, cols:, state: "idle", t:, seed: 1,
    look: look.to_h.except(:particles, :mask, :mix), digest: ascii.digest, lines: ascii.render(look, state: :idle).chars.map(&:join) }
end

trigger = {
  picks: SESSIONS.to_h { |s| [s, Face::Masks.pick(s)] },
  mixes: MIXES.map { |state, t, since, from| { state: state.to_s, t:, since:, from:, mix: Face::Masks.mix(state, t, since:, from:) } },
  morphs: Face::Masks::ORDER.to_h { |mask| [mask, Face::Masks.morph(Face::Masks.params(nil), Face::Masks.params(mask), 0.5)] },
}

path = File.join(__dir__, "..", "test", "fixtures", "face_ascii_frames.json")
File.write(path, "#{JSON.pretty_generate({ schema: 1, tolerance: 0.01, chars: Face::Glyphs::DEFAULT_CHARS, meshes: { cube: CUBE }, cases:, masks:, trigger: })}\n")
puts "wrote #{cases.size} frames and #{masks.size} mask frames to #{path}"
