# frozen_string_literal: true

# What "the engine" is, in one place.
#
# Five different pieces of code have needed to answer "which files is the engine
# made of", and every one of them answered it separately -- three different
# corpora, and the disagreements were not academic. The parse check reported
# "ruby syntax: ok" over a set that excluded all thirty lib/*.rb files, which is
# the check MASTER's autofix has already broken this engine past. Provenance's
# glob went one level deeper than the others and dropped 484 of 610 knobs out of
# every manifest without failing anything.
#
# So this file is the definition and nothing else re-derives it. It deliberately
# has no dependencies -- not on dilla.rb, not on ROOT, not on a gem -- so that
# provenance and the test suite can require it directly without booting the
# engine.
#
# The engine is one file now. It was 81 parts under lib/engine/ required in a
# hand-pinned order, and that order was load-bearing, so concatenating them in
# it is what the order always meant. Two ways the list could lie went with the
# split: a part on disk that nothing required, and a name in the list with no
# file behind it. Neither is expressible any more.
module DillaSources
  class << self
    def root = File.expand_path("..", __dir__)

    # The engine's own program.
    def entry = File.join(root, "dilla.rb")

    # lib/*.rb -- the support modules dilla.rb requires by name. Engine code by
    # every test that matters: they read ENV knobs that change the render, they
    # are what /fix rewrites, and a syntax error in one of them stops a render
    # exactly as dead as one in the entry does.
    def support = Dir[File.join(root, "lib", "*.rb")].sort

    # Every file the engine is made of.
    def all = ([entry] + support).freeze
  end
end
