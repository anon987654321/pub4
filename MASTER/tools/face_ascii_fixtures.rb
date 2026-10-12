# frozen_string_literal: true

# Writes test/fixtures/face_ascii_frames.json: the exact frames the Ruby ASCII
# face draws for fixed (rows, cols, state, t, seed), with the points' digest and
# the Look each came from. The Ruby test asserts them; the web face's port
# asserts the same file under node (cell differences up to "tolerance" are
# allowed, since libm's sin and cos may differ in the last bit between
# runtimes). Run after any change to data/tokens.yml face_interface.ascii or to
# the renderer, and commit the result: `ruby tools/face_ascii_fixtures.rb`.

require "json"
require_relative "../lib/master"

include Master::CLI

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
  ["cube", :cube, 16, 40, :idle, 2.0, 0]
].freeze

def source(kind) = kind == :head ? nil : Face::Mesh.parse(CUBE)

cases = CASES.map do |name, kind, rows, cols, state, t, seed|
  src = source(kind) || Face::Head.for(rows, cols)
  look = Face::Pose.at(state, t, seed)
  ascii = Face::Ascii.new(src, rows, cols, chars: Face::Glyphs::DEFAULT_CHARS, mode: "dark")
  { name:, source: kind == :head ? { kind: "head" } : { kind: "mesh", ref: "cube" }, rows:, cols:, state: state.to_s, t:, seed:,
    look: look.to_h.except(:particles), digest: ascii.digest, lines: ascii.render(look, state:).chars.map(&:join) }
end

path = File.join(__dir__, "..", "test", "fixtures", "face_ascii_frames.json")
File.write(path, "#{JSON.pretty_generate({ schema: 1, tolerance: 0.01, chars: Face::Glyphs::DEFAULT_CHARS, meshes: { cube: CUBE }, cases: })}\n")
puts "wrote #{cases.size} frames to #{path}"
