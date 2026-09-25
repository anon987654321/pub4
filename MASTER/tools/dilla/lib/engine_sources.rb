# frozen_string_literal: true

# What "the engine" is, in one place: dilla.rb plus lib/*.rb.
# sprawl: deliberate -- it has no dependencies, so it cannot fold into a file that has.
#
# Provenance, the parse check and the test suite all ask which files the engine
# is made of, and this file is the only answer, so no caller re-derives a corpus
# of its own. It has no dependencies -- not on dilla.rb, not on ROOT, not on a
# gem -- so those callers can require it without booting the engine.
#
# The engine is one file, with its parts inline in load order. The live scripts
# in lib/ are named apart below; STUDIO/gate.rb counts every support file against
# DILLA_SUPPORT_CEILING, which is a separate question from what the engine loads.
module DillaSources
  class << self
    def root = File.expand_path("..", __dir__)

    # The engine's own program.
    def entry = File.join(root, "dilla.rb")

    # lib/*.rb -- the support modules dilla.rb requires by name. Engine code by
    # every test that matters: they read ENV knobs that change the render, they
    # are what /fix rewrites, and a syntax error in one of them stops a render
    # exactly as dead as one in the entry does.
    def support = Dir[File.join(root, "lib", "*.rb")].sort - live

    # The live side lives in lib/ too and is not the engine: the livesets and the
    # sine stream are run by `dilla live` and `dilla sines`, never required by
    # dilla.rb, and they carry their own helpers under names the engine's census
    # would read as its own uncalled methods and unguarded filters.
    def live = %w[livesets sine_stream].map { |name| File.join(root, "lib", "#{name}.rb") }

    # Every file the engine is made of.
    def all = ([entry] + support).freeze
  end
end
