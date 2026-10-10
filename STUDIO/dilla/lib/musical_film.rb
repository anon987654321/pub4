# frozen_string_literal: true

require_relative "midi_effects"
require_relative "scene"

module DillaMusicalFilm
  CHAINS = {
    intro: :film_intro,
    verse: :film_motion,
    bridge: :film_motion,
    hook: :film_hook,
    solo: :film_alien,
    breakdown: :film_breakdown,
    outro: :film_intro
  }.freeze

  MOTIFS = {
    city: [0, 3, 5, 10, 7],
    night: [0, 2, 7, 9, 11],
    machine: [0, 1, 6, 8, 10],
    dream: [0, 4, 7, 9, 14],
    gravity: [0, 3, 7, 10, 12]
  }.freeze

  WORLD_EVENT_BY_PHASE = {
    intro: :void,
    verse: :debris,
    bridge: :radio,
    hook: :laser,
    solo: :flash,
    breakdown: :fracture,
    outro: :bloom
  }.freeze

  module_function

  def plan(scene:, index:, total:, seed:, tension:, energy:, bpm: 84.0, root: 60)
    world = DillaScene.profile(scene, index:, tension:, energy:)
    phase = DillaScene.journey(index, total)
    rng = Random.new(seed.to_i ^ (index * 0x9E37))
    beat = 60.0 / bpm.to_f.clamp(40.0, 180.0)
    degrees = MOTIFS.fetch(world.fetch(:family).to_sym, MOTIFS[:city])
    motif = DillaMidiEffects.motif_events(
      degrees: degrees,
      root: root,
      at: 0.0,
      beat:,
      rhythm: [0.5, 0.75, 0.25, 0.5, 1.0],
      gain: 0.42
    )
    chain = CHAINS.fetch(phase)
    transformed = DillaMidiEffects.apply(
      motif,
      name: chain,
      rng:,
      params: DillaMidiEffects::DEFAULTS.merge(scale_pcs: scale_pcs(root, world))
    )
    critique = critique(motif, transformed, world:)
    mutation = mutation_for(critique, phase:)
    {
      scene: scene.to_s,
      phase:,
      family: world.fetch(:family),
      motif: motif.map(&:to_h),
      events: transformed.map(&:to_h),
      midi_chain: chain.to_s,
      voices: world.fetch(:voices),
      world_event: WORLD_EVENT_BY_PHASE.fetch(phase),
      dynamic: world.fetch(:dynamic),
      architecture: world.fetch(:architecture),
      critique:,
      mutation:,
      next_scene: next_scene(phase)
    }
  end

  def scale_pcs(root, world)
    octave = root.to_i % 12
    intervals = case world.fetch(:family).to_sym
                when :machine then [0, 1, 3, 6, 8, 10]
                when :dream then [0, 2, 4, 7, 9, 11]
                else [0, 2, 3, 5, 7, 9, 10]
                end
    intervals.map { |n| (octave + n) % 12 }
  end

  def critique(original, transformed, world:)
    source_pcs = original.map { |event| event.midi % 12 }.uniq
    output_pcs = transformed.map { |event| event.midi % 12 }.uniq
    span = transformed.map(&:midi).then { |notes| notes.empty? ? 0 : notes.max - notes.min }
    times = transformed.map(&:at).sort
    gaps = times.each_cons(2).map { |a, b| (b - a).abs }
    repetition = source_pcs.empty? ? 0.0 : 1.0 - (output_pcs - source_pcs).length.fdiv([output_pcs.length, 1].max)
    empty_space = gaps.empty? ? 1.0 : gaps.count { |gap| gap > 0.55 }.fdiv(gaps.length)
    change = (output_pcs.length - source_pcs.length).abs.fdiv([source_pcs.length, 1].max)
    memorable = (span.clamp(0, 24) / 24.0 * 0.35) + (change.clamp(0, 1) * 0.25) + ((1.0 - (repetition - 0.7).abs).clamp(0, 1) * 0.4)
    contrast = (world.fetch(:contrast) * 0.55 + (1.0 - empty_space).abs * 0.45).clamp(0.0, 1.0)
    {
      happened: transformed.length > 1,
      remained: repetition.round(3),
      contrast: contrast.round(3),
      empty_space: empty_space.round(3),
      strange_but_intentional: change.clamp(0.0, 1.0).round(3),
      memorable: memorable.round(3),
      score: (memorable * 0.45 + contrast * 0.25 + repetition * 0.2 + (span > 4 ? 0.1 : 0.0)).clamp(0.0, 1.0).round(3)
    }
  end

  def mutation_for(critique, phase:)
    return { action: :fragment, chain: :film_breakdown } if critique.fetch(:score) < 0.46
    return { action: :open_space, chain: :film_breakdown } if critique.fetch(:empty_space) < 0.12
    return { action: :restate, chain: CHAINS.fetch(phase) } if critique.fetch(:remained) < 0.38
    { action: :advance, chain: CHAINS.fetch(next_scene(phase)) }
  end

  def next_scene(phase)
    case phase
    when :intro then :verse
    when :verse then :hook
    when :bridge then :hook
    when :hook then :solo
    when :solo then :breakdown
    when :breakdown then :outro
    else :outro
    end
  end

  def demo(seed: 16_842)
    scenes = %w[flylo flylo_haze_01 flylo_massage_situation flylo_computer_face flylo_haze_05]
    scenes.each_with_index.map do |scene, index|
      plan(scene:, index:, total: scenes.length, seed:, tension: index.fdiv([scenes.length - 1, 1].max), energy: 0.34 + index * 0.12)
    end
  end
end
