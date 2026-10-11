# frozen_string_literal: true

require "yaml"

# Boom-bap and Dilla drum patterns as data: step grids at 16th resolution plus
# per-instrument micro-timing in whole ticks at 96 PPQ. The pick is a pure
# function of the render seed, so a seed always yields the same pattern. While a
# pattern is active, drum_pattern_pick reads its grids and DillaGroove reads its
# tick offsets instead of the GROOVE_FEELS table.
module DillaBeatLibrary
  PATH = File.expand_path("../data/boom_bap_patterns.yml", __dir__).freeze
  DATA = YAML.safe_load_file(PATH, aliases: false).freeze
  PATTERNS = DATA.fetch("patterns").freeze
  BOUNDS = DATA.fetch("bounds").transform_keys(&:to_sym).freeze
  ROLE_GRIDS = { kicks: "kicks", snares: "snares", hats: "hats", ghosts: "ghosts" }.freeze

  @active = nil

  class << self
    attr_reader :active

    def names = PATTERNS.keys.sort

    # Same seed, same name. BEAT_PATTERN forces one by name.
    def pick_name(seed, family: nil)
      forced = ENV["BEAT_PATTERN"].to_s.strip
      return forced if PATTERNS.key?(forced)

      pool = names.select { |n| family.nil? || PATTERNS[n]["family"] == family.to_s }
      pool.fetch(seed.to_i % pool.length)
    end

    def activate!(seed, family: nil)
      @active = pick_name(seed, family:)
    end

    def deactivate! = (@active = nil)

    def enabled? = !@active.nil?

    # The bar's steps for a drum_pattern_pick role, or nil when nothing applies.
    def steps_for(role, bar, name = @active)
      return nil unless name && (key = ROLE_GRIDS[role.to_sym])

      pool = PATTERNS.fetch(name).fetch(key)
      Array(pool[bar % pool.length]).sort
    end

    def instrument_for(role)
      case role.to_sym
      when :kick, :kick_anchor, :kick_sync then :kick
      when :snare, :clap then :snare
      when :hat, :hat_down, :hat_up, :open then :hat
      when :ghost, :perc then :ghost
      end
    end

    # Whole ticks for this role at this step, clamped to the stated bounds; nil
    # when no pattern is active or the role is not a drum.
    def tick_offset(role, step, name = @active)
      inst = instrument_for(role)
      return nil unless name && inst

      pat = PATTERNS.fetch(name)
      s = step.to_i
      ticks = pat.fetch("ticks").fetch(inst.to_s, 0)
      ticks += pat.fetch("swing_ticks", {}).fetch(inst.to_s, 0) if s.odd?
      ticks += pat.fetch("nudge", {}).fetch(inst.to_s, {}).fetch(s, 0)
      lo, hi = BOUNDS.fetch(inst)
      ticks.clamp(lo, hi)
    end
  end
end
