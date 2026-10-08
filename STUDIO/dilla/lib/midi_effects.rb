# frozen_string_literal: true

require "yaml"

module DillaMidiEffects
  Event = Data.define(:midi, :at, :held, :gain, :role) do
    def to_h
      { midi: midi, at: at, held: held, gain: gain, role: role }
    end
  end

  ROOT = File.expand_path("..", __dir__)
  CONFIG_PATH = File.join(ROOT, "data", "midi_effects.yml")
  CONFIG = YAML.safe_load_file(CONFIG_PATH, aliases: false).freeze
  DEFAULTS = CONFIG.fetch("parameters").transform_keys(&:to_sym).freeze

  module_function

  def chains
    CONFIG.fetch("chain").transform_keys(&:to_sym)
  end

  def chain(name)
    chains.fetch(name.to_sym) { chains.fetch(:default) }
  end

  def normalize(events)
    Array(events).map do |event|
      event.is_a?(Event) ? event : Event.new(
        event.fetch(:midi, event["midi"]).to_i,
        event.fetch(:at, event["at"]).to_f,
        event.fetch(:held, event["held"]).to_f,
        event.fetch(:gain, event["gain"]).to_f,
        event.fetch(:role, event["role"] || :lead).to_sym
      )
    end
  end

  def apply(events, name: :default, rng:, params: DEFAULTS)
    out = normalize(events)
    chain(name).each { |effect| out = send(effect.to_sym, out, rng:, params:) }
    out.sort_by { |event| [event.at, event.midi] }
  end

  def scale(events, rng:, params:)
    pcs = Array(params[:scale_pcs]).map(&:to_i).uniq
    return events if pcs.empty?

    events.map do |event|
      next event if pcs.include?(event.midi % 12)

      offsets = (1..6).flat_map { |distance| [-distance, distance] }
      shift = offsets.find { |distance| pcs.include?((event.midi + distance) % 12) }
      event.with(midi: event.midi + shift)
    end
  end

  def probability(events, rng:, params:)
    odds = params.fetch(:probability).to_f.clamp(0.0, 1.0)
    events.select { |_| rng.rand <= odds }
  end

  def microshift(events, rng:, params:)
    width = params.fetch(:microshift_ms).to_f.abs / 1000.0
    events.map { |e| e.with(at: e.at + rng.rand(-width..width)) }
  end

  def velocity_curve(events, rng:, params:)
    events.each_with_index.map do |event, index|
      phase = index % 4
      accent = [1.08, 0.92, 1.0, 1.14].fetch(phase)
      event.with(gain: (event.gain * accent).clamp(0.0, 1.0))
    end
  end

  def ratchet(events, rng:, params:)
    max = params.fetch(:ratchet_max).to_i.clamp(1, 4)
    events.flat_map do |event|
      n = rng.rand < 0.32 ? rng.rand(2..max) : 1
      next [event] if n == 1

      slice = event.held / n
      Array.new(n) do |i|
        event.with(
          at: event.at + (slice * i),
          held: [slice * 0.86, 0.02].max,
          gain: event.gain * (1.0 - i * 0.11)
        )
      end
    end
  end

  def ghost(events, rng:, params:)
    odds = params.fetch(:ghost_probability).to_f.clamp(0.0, 1.0)
    additions = events.filter_map do |event|
      next unless rng.rand < odds

      event.with(
        at: event.at + event.held * 0.52,
        held: [event.held * 0.22, 0.025].max,
        gain: event.gain * 0.28
      )
    end
    events + additions
  end

  def fragment(events, rng:, params:)
    return events if events.length < 3

    odds = params.fetch(:fragment_probability).to_f.clamp(0.0, 1.0)
    return events unless rng.rand < odds

    keep = rng.rand(2..[events.length, 4].min)
    events.first(keep) + events.last(1)
  end

  def mirror(events, rng:, params:)
    return events if events.length < 2

    pivot = events.first.midi
    events.map.with_index do |event, index|
      mirrored = pivot + (pivot - event.midi)
      event.with(midi: mirrored.clamp(24, 108), gain: event.gain * (index.even? ? 1.0 : 0.92))
    end
  end

  def octave_bloom(events, rng:, params:)
    odds = params.fetch(:octave_probability).to_f.clamp(0.0, 1.0)
    span = params.fetch(:octave_span).to_i
    events.flat_map do |event|
      next [event] unless rng.rand < odds

      [event, event.with(midi: (event.midi + span).clamp(24, 108), gain: event.gain * 0.26)]
    end
  end

  # Turn a motif's scale degrees into a MIDI phrase. Repeated degrees are
  # allowed; their memory stays with the motif rather than being erased by the
  # effect chain.
  def transpose(events, rng:, params:)
    semitones = params.fetch(:transpose).to_i
    events.map { |event| event.with(midi: event.midi + semitones) }
  end

  def chord(events, rng:, params:)
    intervals = Array(params.fetch(:chord_intervals)).map(&:to_i)
    spread = params.fetch(:chord_gain).to_f.clamp(0.0, 1.0)
    events.flat_map do |event|
      [event, *intervals.map { |interval| event.with(midi: (event.midi + interval).clamp(24, 108), gain: event.gain * spread) }]
    end
  end

  def invert(events, rng:, params:)
    return events if events.empty?

    pivot = events.map(&:midi).sum.to_f / events.length
    events.map { |event| event.with(midi: (pivot + (pivot - event.midi)).round.clamp(24, 108)) }
  end

  def arp(events, rng:, params:)
    return events if events.length < 2

    ordered = events.sort_by(&:midi)
    step = [ordered.map(&:held).sum / ordered.length, 0.04].max
    events.each_with_index.map do |event, index|
      note = ordered[index % ordered.length].midi
      event.with(midi: note, at: event.at + (index % ordered.length) * step * 0.16)
    end
  end

  def note_repeat(events, rng:, params:)
    count = params.fetch(:note_repeat).to_i.clamp(1, 6)
    return events if count <= 1

    events.flat_map do |event|
      slice = event.held / count
      Array.new(count) do |index|
        event.with(
          at: event.at + (slice * index),
          held: [slice * 0.72, 0.018].max,
          gain: event.gain * (1.0 - index * 0.06)
        )
      end
    end
  end

  def euclidean(events, rng:, params:)
    steps = params.fetch(:euclidean_steps).to_i.clamp(1, 32)
    pulses = params.fetch(:euclidean_pulses).to_i.clamp(1, steps)
    events.each_with_index.select { |_, index| ((index * pulses) % steps) < pulses }.map(&:first)
  end

  def humanize(events, rng:, params:)
    width = params.fetch(:humanize_ms).to_f.abs / 1000.0
    gain = params.fetch(:humanize_gain).to_f.abs
    events.map do |event|
      event.with(
        at: event.at + rng.rand(-width..width),
        gain: (event.gain + rng.rand(-gain..gain)).clamp(0.0, 1.0)
      )
    end
  end

  def grace_notes(events, rng:, params:)
    interval = params.fetch(:grace_interval).to_i
    amount = params.fetch(:grace_gain).to_f.clamp(0.0, 1.0)
    events.flat_map do |event|
      grace_at = [event.at - [event.held * 0.18, 0.035].max, 0.0].max
      grace = event.with(
        midi: (event.midi + interval).clamp(24, 108),
        at: grace_at,
        held: [event.held * 0.12, 0.018].max,
        gain: event.gain * amount,
        role: :grace
      )
      [grace, event]
    end
  end

  def reverse(events, rng:, params:)
    return events if events.length < 2

    start = events.map(&:at).min
    finish = events.map { |event| event.at + event.held }.max
    events.map do |event|
      new_at = start + (finish - (event.at + event.held))
      event.with(at: new_at)
    end
  end

  def mirror(events, rng:, params:)
    return events if events.length < 2

    pivot = events.first.midi
    events.map.with_index do |event, index|
      mirrored = pivot + (pivot - event.midi)
      event.with(midi: mirrored.clamp(24, 108), gain: event.gain * (index.even? ? 1.0 : 0.92))
    end
  end

  def stutter(events, rng:, params:)
    return events if events.length < 2

    repeats = params.fetch(:stutter_repeats).to_i.clamp(2, 6)
    fragment = events.first([events.length, params.fetch(:stutter_events).to_i.clamp(1, events.length)].min)
    span = [fragment.map { |event| event.held }.sum, 0.08].max
    fragment.flat_map do |event|
      Array.new(repeats) do |index|
        event.with(at: event.at + (index * span), gain: event.gain * (1.0 - index * 0.08))
      end
    end
  end

  def gate(events, rng:, params:)
    amount = params.fetch(:gate_ratio).to_f.clamp(0.08, 1.0)
    events.map { |event| event.with(held: [event.held * amount, 0.018].max) }
  end

  def hocket(events, rng:, params:)
    voices = Array(params.fetch(:hocket_voices)).map(&:to_sym)
    voices = %i[call response] if voices.empty?
    events.each_with_index.map { |event, index| event.with(role: voices[index % voices.length]) }
  end

  def call_response(events, rng:, params:)
    split = (events.length / 2.0).ceil
    events.each_with_index.map do |event, index|
      event.with(role: index < split ? :call : :response, gain: index < split ? event.gain : event.gain * 0.9)
    end
  end

  # Turn a motif's scale degrees into a MIDI phrase. Repeated degrees are
  # allowed; their memory stays with the motif rather than being erased by the
  # effect chain.
  def motif_events(degrees:, root:, at:, beat:, rhythm:, gain: 0.3, role: :lead)
    degrees.each_with_index.map do |degree, index|
      length = rhythm[index % rhythm.length].to_f * beat
      Event.new(root.to_i + degree.to_i, at.to_f + (index * beat), length, gain.to_f, role.to_sym)
    end
  end
end
