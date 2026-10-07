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
  def motif_events(degrees:, root:, at:, beat:, rhythm:, gain: 0.3, role: :lead)
    degrees.each_with_index.map do |degree, index|
      length = rhythm[index % rhythm.length].to_f * beat
      Event.new(root.to_i + degree.to_i, at.to_f + (index * beat), length, gain.to_f, role.to_sym)
    end
  end
end
