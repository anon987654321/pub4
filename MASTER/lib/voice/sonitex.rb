# frozen_string_literal: true

module Master
  module Voice
  module Sonitex
    module_function

    def processor(**opts)
      SonitexSox.new(**opts)
    end

    def presets
      processor.presets
    end

    def command(input, output, preset: :subtle_vintage)
      processor.command(input, output, preset: preset)
    end

    def process(input, output, preset: :subtle_vintage, noise: nil)
      processor.process(input, output, preset: preset, noise: noise)
    end

    def preset_for_producer(name)
      case name.to_sym
      when :j_dilla, :dilla
        ProductionDna.sonitex_preset_for(:dilla_drum_bus)
      when :flying_lotus, :flylo
        ProductionDna.sonitex_preset_for(:flylo_haze)
      when :madlib
        ProductionDna.sonitex_preset_for(:madlib_303)
      else
        :subtle_vintage
      end
    end

    def brief
      SonitexSox.brief
    end
  end
  end
end
