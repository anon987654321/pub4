# frozen_string_literal: true

require "yaml"

module Master
  # Defines MASTER's behavioral persona and voice style.
  # Default: dark_malay — terse, direct, Osman TTS voice.
  class Personality
    PERSONAS = {
      dark_malay: {
        voice:       "ms-MY-OsmanNeural",
        tts_rate:    "-35%",
        tts_pitch:   "-150Hz",
        style:       :deep,
        description: "Terse. Direct. No filler. Dark."
      },
      british: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Measured. Precise. Dry wit."
      },
      norwegian: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Calm. Considered. Honest."
      }
    }.freeze

    DEFAULT = :dark_malay

    AXIOMS_PATH = File.join(File.expand_path("../../..", __dir__), "data", "axioms.yml").freeze

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def initialize(name = DEFAULT)
      @name    = name.to_sym
      persona  = PERSONAS.fetch(@name, PERSONAS[DEFAULT])
      @voice     = persona[:voice]
      @tts_rate  = persona[:tts_rate]
      @tts_pitch = persona[:tts_pitch]
      @style     = persona[:style]
      @desc      = persona[:description]
    end

    # System prompt fragment injected before every LLM call.
    # Includes kernel axioms and top philosophy principles so LLM internalizes them.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

    def build_system_prompt
      lines = ["You are MASTER. #{@desc} No preambles. No hedges. Respond in plain prose."]
      lines << "" << kernel_axioms_block << "" << top_philosophy_block
      lines.compact.join("\n")
    end

    def kernel_axioms_block
      data    = load_axioms
      kernel  = data&.dig("kernel") || {}
      return nil if kernel.empty?
      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Axioms (enforced)\n#{pairs}"
    end

    def top_philosophy_block
      data  = load_axioms
      items = data&.dig("philosophy", "prioritized_top_25") || []
      return nil if items.empty?
      top5 = items.first(5).map { |a| "  #{a["id"]}: #{a["statement"]}" }.join("\n")
      "## Core Philosophy (top 5)\n#{top5}"
    end

    def load_axioms
      return @axioms if defined?(@axioms)
      @axioms = File.exist?(AXIOMS_PATH) ? YAML.safe_load_file(AXIOMS_PATH) : nil
    rescue StandardError
      @axioms = nil
    end
  end
end
