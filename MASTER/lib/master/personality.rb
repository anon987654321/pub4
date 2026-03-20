# frozen_string_literal: true

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

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def initialize(name = DEFAULT, root: nil)
      @name    = name.to_sym
      persona  = PERSONAS.fetch(@name, PERSONAS[DEFAULT])
      @voice     = persona[:voice]
      @tts_rate  = persona[:tts_rate]
      @tts_pitch = persona[:tts_pitch]
      @style     = persona[:style]
      @desc      = persona[:description]
      @axioms    = Axioms.new(root:)
    end

    # System prompt fragment injected before every LLM call.
    # Includes kernel axioms and top philosophy principles so LLM internalizes them.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

    def build_system_prompt
      lines = ["You are MASTER. #{@desc} No preambles. No hedges. Respond in plain prose."]
      kb    = @axioms.kernel_block
      pb    = @axioms.philosophy_block(limit: 5)
      lines << "" << kb   if kb
      lines << "" << pb   if pb
      lines.join("\n")
    end
  end
end
