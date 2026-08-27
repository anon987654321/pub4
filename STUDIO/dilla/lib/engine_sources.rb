# frozen_string_literal: true

# What "the engine" is, in one place.
#
# Five different pieces of code have needed to answer "which files is the engine
# made of", and every one of them answered it separately:
#
#   dilla.rb              ENGINE_SOURCES = dilla.rb + lib/engine/*.rb
#   cli_commands.rb       that, plus Dir[lib/*.rb], spelled out twice
#   provenance.rb         dilla.rb + Dir[lib/**/*.rb]
#   analysis.rb           ENGINE_SOURCES (so lib/*.rb was never parse-checked)
#   stream.rb             engine_mtime over ENGINE_SOURCES
#
# Three different corpora, and the disagreements were not academic. The parse
# check reported "ruby syntax: ok" over a set that excluded all thirty lib/*.rb
# files, which is the check MASTER's autofix has already broken this engine
# past. Provenance's glob went one level deeper than the others and, when the
# engine split into lib/engine/, dropped 484 of 610 knobs out of every manifest
# without failing anything.
#
# So this file is the definition and nothing else re-derives it. It deliberately
# has no dependencies -- not on dilla.rb, not on ROOT, not on a gem -- so that
# provenance and the test suite can require it directly without booting the
# engine.
module DillaSources
  # The engine's own top-level program, split by concern. Required in the order
  # they were written in, which is load-bearing: constants in these files are
  # computed at load time from ones above them, and reordering silently changes
  # their values. This list moved here from dilla.rb; dilla.rb still drives the
  # requires, it no longer owns the list.
  # audio_graph leads because it depends on nothing: it is a graph builder that
  # returns a string, so any part below it may hand it channels. %w[] takes no
  # comments, which is why this one is here and not beside the entry.
  ENGINE_PARTS = %w[
    audio_graph
    source_learn
    track_tables
    voice_presets
    render_seed
    patch
    radio_bergen
    resolve_config
    progression_build
    groove_timing
    percussion
    drum_policy
    render_scratch
    drum_bus
    sample_loops
    bus_filters
    render_helpers
    drum_bus_filter
    master_chain
    form_map
    lead_arp
    lead_melodic
    engine_defaults
    drum_patterns
    chord_tables
    progression_tables
    chord_theory
    shell
    cli_commands
    analysis
    grade_analog
    setlist
    speech
    live_play
    style_defaults
    archetypes
    stream_tuning
    env_locks
    stream_iterate
    apply_profiles
    mix_metrics
    showcase
    stream_rotation
    demo_catalog
    demo_all
    stream
    composition_glue
    learned_engine
    dilla_progression
    dilla_drums
    dilla_schedule
    drum_kit
    assets
    synth_samples
    native_synth
    midi_smf
    pad_render
    pad_layers
    lead_render
    render_dilla
    render_industrial
    composition_cmds
    help
    render_analog
    render_madlib
    render_techno
    mix_recipes
    wonky_learn
    rap_vocal
    organic
    crate
    sample_morph
    organic_vary
    tape_master
    rap_vocal_fit
    punk_guitar
    learn_source
    electronium
    characterize
  ].freeze

  class << self
    def root = File.expand_path("..", __dir__)

    # The entry script. The parts cannot use __FILE__ for this: theirs is a
    # part, not the engine.
    def entry = File.join(root, "dilla.rb")

    # lib/engine/*.rb in load order.
    def parts = ENGINE_PARTS.map { |part| File.join(root, "lib", "engine", "#{part}.rb") }

    # lib/*.rb -- the support modules dilla.rb requires by name. Included in
    # `all` because they are engine code by every test that matters: they read
    # ENV knobs that change the render, they are what /fix rewrites, and a
    # syntax error in one of them stops a render exactly as dead as one in a
    # part does.
    def support = Dir[File.join(root, "lib", "*.rb")].sort

    # Every file the engine is made of.
    def all = ([entry] + parts + support).freeze

    # A part on disk that ENGINE_PARTS does not name is never required, so it is
    # dead however good it looks. Returns paths, not slugs, so a caller can put
    # them in a message without rebuilding them.
    def unlisted_parts
      Dir[File.join(root, "lib", "engine", "*.rb")].sort - parts
    end
  end
end
