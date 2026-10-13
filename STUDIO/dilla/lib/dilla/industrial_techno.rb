# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "time"

module Dilla
  # A separate, original industrial-techno engine. The existing Dilla showcase is untouched.
  module IndustrialTechno
    TAU = Math::PI * 2
    ROOTS = [43.65, 46.25, 49.0, 51.91, 55.0].freeze
    MAX_BARS = 32
    module_function

    def run(argv)
      # MASTER selects bars from reference duration and creates a fresh internal seed.
      # Both remain overridable for repeatable, deliberate renders, but need no user input.
      opts = { bpm: nil, bars: nil, seed: nil }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby dilla.rb industrial-techno [options]"
        parser.on("--bpm N", Float) { |v| opts[:bpm] = v }
        parser.on("--bars N", Integer) { |v| opts[:bars] = v }
        parser.on("--seed N", Integer) { |v| opts[:seed] = v }
        parser.on("--out PATH") { |v| opts[:out] = v }
        parser.on("--reference DIR_OR_JSON") { |v| opts[:reference] = v }
        parser.on("-h", "--help") { puts parser; return 0 }
      end.parse!(argv)
      raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      profile = read_profile(opts[:reference])
      bpm = (opts[:bpm] || profile&.fetch("target_bpm", nil) || 138).to_f
      raise ArgumentError, "BPM must be 90..190" unless bpm.finite? && bpm.between?(90, 190)
      plan = generation_plan(profile:, bpm:, bars: opts[:bars], seed: opts[:seed])
      bars, seed = plan.values_at(:bars, :seed)
      raise ArgumentError, "bars must be 1..#{MAX_BARS}" unless bars.between?(1, MAX_BARS)
      path = File.expand_path(opts[:out] || File.join(ENV.fetch("XDG_DATA_HOME", File.expand_path("~/Documents")), "dilla-renders", "industrial-techno-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav"))
      raise ArgumentError, "refusing to overwrite existing output: #{path}" if File.exist?(path)
      render(path, bpm:, bars:, seed:, profile:)
      puts "dilla0: wrote original industrial techno #{path} (#{bpm.round(1)} BPM, #{bars} bars, seed #{seed})"
      puts "dilla0: reference profile applied" if profile
      0
    rescue ArgumentError, JSON::ParserError => error
      warn "dilla0: #{error.message}"
      2
    rescue StandardError => error
      warn "dilla0: render failed (#{error.class}: #{error.message})"
      1
    end

    # Infer arrangement length from the measured source duration. A full reference
    # can be longer than this renderer's cap, so keep the plan within safe limits.
    # The seed is generated inside Dilla and printed in the render log for traceability.
    def generation_plan(profile:, bpm:, bars: nil, seed: nil)
      duration = begin
        Float(profile&.fetch("source_duration_seconds", nil))
      rescue ArgumentError, TypeError
        nil
      end
      inferred_bars = duration&.positive? ? (duration * bpm.to_f / 240.0).round.clamp(8, MAX_BARS) : 16
      { bars: (bars || inferred_bars).to_i, seed: seed.nil? ? (Random.new_seed & 0xffff_ffff) : seed.to_i }
    end

    def render(path, bpm: 138, bars: nil, seed: nil, profile: nil)
      plan = generation_plan(profile:, bpm:, bars:, seed:)
      bars, seed = plan.values_at(:bars, :seed)
      raise ArgumentError, "bars must be 1..#{MAX_BARS}" unless bars.between?(1, MAX_BARS)
      beat = 60.0 / bpm.to_f
      step = beat / 4.0
      frames = (bars * 4 * beat * SAMPLE_RATE).round
      rng = Random.new(seed)
      root = ROOTS.sample(random: rng)
      pattern = events(bars, rng, root:, step:, profile:)
      p = profile&.fetch("parameters", {}) || {}
      rumble_level = Float(p.fetch("rumble_level", 0.14)).clamp(0.05, 0.35)
      duck_depth = Float(p.fetch("rumble_duck_depth", 0.82)).clamp(0.3, 0.95)
      drive = Float(p.fetch("distortion_drive", 2.0)).clamp(1.0, 4.0)
      break_start = bars >= 8 ? (bars * 0.72).floor : bars + 1
      break_end = bars >= 8 ? [(bars * 0.84).floor, break_start + 1].max : break_start
      brown = 0.0
      prev_noise = 0.0
      FileUtils.mkdir_p(File.dirname(path))
      WAV.write_stream(path, frames:, channels: 2, bits: 24, block_size: 8192) do |offset, count|
        left = Array.new(count, 0.0)
        right = Array.new(count, 0.0)
        count.times do |local|
          i = offset + local
          time = i.to_f / SAMPLE_RATE
          beat_i = (time / beat).floor
          beat_age = time - beat_i * beat
          bar = beat_i / 4
          step_i = (time / step).floor
          step_age = time - step_i * step
          noise = rng.rand * 2.0 - 1.0
          gap = bars >= 8 && bar >= break_start && bar < break_end
          kick_env = gap ? 0.0 : Math.exp(-beat_age * 10.5)
          phase = TAU * (45 * beat_age + 105.0 / 24 * (1.0 - Math.exp(-24 * beat_age)))
          kick = gap ? 0.0 : Math.sin(phase) * kick_env * 0.82 + Math.sin(TAU * 2100 * beat_age) * Math.exp(-beat_age * 190) * 0.12
          brown = brown * 0.997 + noise * 0.025
          duck = 1.0 - kick_env * duck_depth
          rumble = (Math.sin(TAU * root * time) * rumble_level +
                    Math.sin(TAU * root * 1.4142 * time) * rumble_level * 0.39 + brown * rumble_level) * duck
          level = gap ? 0.18 : (bar < 4 ? 0.35 : (bar < 8 ? 0.58 : (bar < 12 ? 0.92 : 1.0)))
          drone = level * (Math.sin(TAU * root * 1.4983 * time) * 0.07 +
                           Math.sin(TAU * root * 2.003 * time) * 0.045 +
                           Math.sin(TAU * root * 2.997 * time) * 0.026) * duck
          bass = 0.0
          if (event = pattern[:bass][step_i]) && step_age < event[:length]
            bphase = TAU * event[:frequency] * step_age
            saw = 2.0 * ((bphase / TAU) % 1.0) - 1.0
            bass = (Math.sin(bphase) * 0.6 + saw * 0.4) * Math.exp(-step_age * event[:decay]) * event[:gain] * level * duck
          end
          clang = 0.0
          pan_m = 0.0
          if (event = pattern[:metal][step_i]) && step_age < event[:decay] * 5
            env = Math.exp(-step_age / event[:decay])
            mphase = TAU * (event[:frequency] * step_age + event[:sweep] * (1.0 - Math.exp(-step_age * 18)) / 18)
            clang = event[:gain] * env * (Math.sin(mphase) + 0.45 * Math.sin(mphase * 1.414) + 0.22 * Math.sin(mphase * 2.31))
            pan_m = event[:pan]
          end
          hat = 0.0
          pan_h = 0.0
          if (event = pattern[:hats][step_i]) && step_age < 0.09
            hat = (noise - prev_noise) * event[:gain] * Math.exp(-step_age * event[:decay])
            pan_h = event[:pan]
          end
          prev_noise = noise
          mono = Math.tanh((kick + rumble + drone + bass + clang + hat + noise * level * 0.012) * drive) / Math.tanh(drive)
          side = clang * pan_m * 0.42 + hat * pan_h * 0.65
          left[local] = ((mono - side) * 0.78).clamp(-0.98, 0.98)
          right[local] = ((mono + side) * 0.78).clamp(-0.98, 0.98)
        end
        [left, right]
      end
      path
    end

    def events(bars, rng, root:, step:, profile:)
      p = profile&.fetch("parameters", {}) || {}
      metal_chance = Float(p.fetch("metal_probability", 0.15)).clamp(0.02, 0.45)
      hat_chance = Float(p.fetch("hat_probability", 0.68)).clamp(0.1, 0.98)
      metal, hats, bass = {}, {}, {}
      motif = [0, 3, 5, 8, 10, 7, 5, 2, 0, 3, 6, 10, 8, 5, 3, 2]
      (bars * 16).times do |index|
        bar = index / 16
        pos = index % 16
        next if bar.zero?
        if pos.even? || rng.rand < hat_chance
          hats[index] = { gain: pos % 8 == 0 ? 0.15 : 0.085, pan: rng.rand * 1.5 - 0.75, decay: 42 + rng.rand * 34 }
        end
        if [0, 6, 10].include?(pos) || (pos == 14 && rng.rand < 0.55)
          midi = motif[(bar * 3 + pos) % motif.size]
          bass[index] = { frequency: root * 2.0**(midi / 12.0), gain: 0.10 + rng.rand * 0.09,
                          decay: 5.0 + rng.rand * 5.0, length: step }
        end
        next if bar < 2
        next unless rng.rand < metal_chance || pos == 14
        metal[index] = { frequency: [277.0, 311.0, 419.0, 503.0, 613.0, 827.0, 1103.0, 1451.0].sample(random: rng),
                         sweep: 90.0 + rng.rand * 820.0, gain: 0.12 + rng.rand * 0.13,
                         pan: rng.rand * 1.7 - 0.85, decay: 0.16 + rng.rand * 0.42 }
      end
      { metal:, hats:, bass: }
    end

    def read_profile(path)
      candidate = if path
                    expanded = File.expand_path(path)
                    File.directory?(expanded) ? File.join(expanded, "profile.json") : expanded
                  else
                    File.join(Reference::REFERENCE_ROOT, "latest_profile.json")
                  end
      return nil unless File.file?(candidate)
      profile = JSON.parse(File.read(candidate))
      raise ArgumentError, "profile genre must be industrial_techno" unless profile["genre"] == "industrial_techno"
      profile
    end
  end
end
