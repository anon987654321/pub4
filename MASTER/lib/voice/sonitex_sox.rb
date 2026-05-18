# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module Master
  module Voice
  class SonitexSox
    Error = Class.new(StandardError)

    STAGES = {
      mix: "compression and density",
      distortion: "frequency-shaped saturation",
      vinyl: "bandwidth, head bump, and pseudo-wear",
      tone: "playback-system EQ",
      noise: "optional surface noise mix",
      sampling: "sample-rate and bit-depth degradation"
    }.freeze

    GAPS = [
      "SoX cannot authentically model STX wow/flutter; use rubberband or a VST for pitch instability.",
      "SoX has overdrive, not the STX saturation/distortion/amp/digital model set.",
      "SoX noise generation lacks vinyl crackle, pops, clicks, sibilance, and program-dependent density.",
      "SoX handles tone/EQ and sampler-style rate/bit reduction best."
    ].freeze

    PRESETS = {
      subtle_vintage: {
        chain: [
          %w[gain -3],
          %w[compand 0.3,1.2 6:-70,-60,-20,-18,0,-3 -2 -90 0.2],
          %w[overdrive 8 30],
          %w[highpass -2 35 0.707q],
          %w[lowpass -2 16000 0.707q],
          %w[bass +1 100 0.3s],
          %w[treble -0.5 12000 0.5s],
          %w[norm -3],
          %w[dither -s]
        ],
        description: "STX-style gentle cumulative degradation: glue, warmth, vinyl bandwidth, no obvious noise."
      },
      aggressive_lofi: {
        chain: [
          %w[gain -2],
          %w[compand 0.1,0.5 6:-60,-50,-15,-12,0,-6 -3 -90 0.1],
          %w[overdrive 15 25],
          %w[highpass 150],
          %w[lowpass 8000],
          %w[bandpass 400 6000]
        ],
        bit_depth: 12,
        sample_rate: 11_025,
        final_chain: [%w[lowpass 9000], %w[dither -s]],
        description: "Severe bandwidth and sampler degradation for dirty lo-fi texture."
      },
      boom_bap: {
        chain: [
          %w[compand 0.05,0.3 6:-70,-60,-25,-20,0,-5 -3 -90 0.05]
        ],
        bit_depth: 12,
        sample_rate: 26_040,
        final_chain: [%w[lowpass 10000], %w[overdrive 5 15], %w[norm -2], %w[dither -s]],
        description: "SP-1200/S950-inspired drum-bus crunch, punch, and bandwidth limit."
      },
      phone_wear: {
        chain: [
          %w[highpass 300],
          %w[lowpass 3400],
          %w[equalizer 800 2q +4],
          %w[overdrive 6 20],
          %w[norm -3],
          %w[dither -s]
        ],
        description: "Mid-forward phone/radio wear effect."
      }
    }.freeze

    attr_reader :sox

    def initialize(sox: nil)
      @sox = sox || self.class.find_sox
    end

    def self.find_sox
      ENV["SOX"].to_s.then { |path| return path if !path.empty? && File.executable?(path) }
      %w[/usr/local/bin/sox /usr/bin/sox sox].find { |path| executable_command?(path) }
    end

    def self.executable_command?(path)
      return File.executable?(path) if path.include?(File::SEPARATOR)

      system("command", "-v", path, out: File::NULL, err: File::NULL)
    end

    def self.brief
      lines = ["Sonitex STX-1260-inspired SoX policy:"]
      lines << "- six stages: #{STAGES.map { |name, desc| "#{name}=#{desc}" }.join('; ')}"
      lines.concat(GAPS.map { |gap| "- #{gap}" })
      lines << "- best results come from cumulative subtle stages, not one extreme effect."
      lines.join("\n")
    end

    def command(input, output, preset: :subtle_vintage)
      profile = fetch_preset(preset)
      [sox!, input.to_s, output.to_s, *flatten_effects(profile.fetch(:chain))]
    end

    def process(input, output, preset: :subtle_vintage, noise: nil)
      profile = fetch_preset(preset)
      if profile[:bit_depth] || profile[:sample_rate] || noise
        process_staged(input, output, profile, noise)
      else
        run(command(input, output, preset: preset))
      end
      output
    end

    def presets
      PRESETS.transform_values { |profile| profile.fetch(:description) }
    end

    private

    def fetch_preset(name)
      PRESETS.fetch(name.to_sym) { raise Error, "unknown sonitex preset: #{name}" }
    end

    def process_staged(input, output, profile, noise)
      Dir.mktmpdir("master-sonitex-") do |dir|
        current = run_stage(input, File.join(dir, "stage.wav"), profile.fetch(:chain))
        current = mix_noise(current, File.join(dir, "noise.wav"), noise) if noise
        current = crush(current, dir, profile) if profile[:bit_depth] || profile[:sample_rate]
        run([sox!, current, output.to_s, *flatten_effects(profile.fetch(:final_chain, [%w[norm -3], %w[dither -s]]))])
      end
    end

    def run_stage(input, output, effects)
      run([sox!, input.to_s, output.to_s, *flatten_effects(effects)])
      output
    end

    def mix_noise(input, output, noise)
      raise Error, "noise sample missing: #{noise}" unless File.file?(noise.to_s)

      run([sox!, "-m", input.to_s, "-v", "0.04", noise.to_s, output])
      output
    end

    def crush(input, dir, profile)
      bit_file = File.join(dir, "bit.wav")
      rate_file = File.join(dir, "rate.wav")
      args = [sox!, input.to_s]
      args.concat(["-b", profile[:bit_depth].to_s]) if profile[:bit_depth]
      args << bit_file
      run(args)
      return bit_file unless profile[:sample_rate]

      run([sox!, bit_file, "-r", profile[:sample_rate].to_s, rate_file, "sinc", "-a", "100"])
      rate_file
    end

    def flatten_effects(effects)
      effects.flat_map { |effect| Array(effect).map(&:to_s) }
    end

    def sox!
      raise Error, "sox not found; set SOX=/path/to/sox" unless sox

      sox
    end

    def run(argv)
      _out, err, status = Open3.capture3(*argv)
      raise Error, err.strip.empty? ? "sox failed" : err.strip unless status.success?
    end
  end
  end
end
