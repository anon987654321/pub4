# frozen_string_literal: true

module Master
  module Voice
  # CouncilFace — persona → voice, blendshape bias, spatial lane for council:speech.
  # Every persona speaks in the single voice data/voice.yml locks; only the
  # blendshape bias and spatial lane differ per persona. These six entries used
  # to name :ryan literally, so a voice.yml flip silently left council:speech
  # on the old voice while every other path moved.
    module CouncilFace
      def self.locked_voice = Policy.single_voice_key

      PERSONAS = {
        "Architect" => {
          position: :left,
          label: "Architect",
          blendshape_bias: { brow: 0.72, jaw: 0.42, lid_open: 0.78 },
          viseme_lane: :left,
        },
        "Skeptic" => {
          position: :right,
          label: "Skeptic",
          blendshape_bias: { brow: 0.82, jaw: 0.28, lid_open: 0.62 },
          viseme_lane: :right,
        },
        "Pragmatist" => {
          position: :center,
          label: "Pragmatist",
          blendshape_bias: { brow: 0.48, jaw: 0.55, smile: 0.32 },
          viseme_lane: :center,
        },
        "Security" => {
          position: :right,
          label: "Security",
          blendshape_bias: { brow: 0.76, jaw: 0.35, lid_open: 0.58 },
          viseme_lane: :right,
        },
        "User" => {
          position: :center,
          label: "User",
          blendshape_bias: { brow: 0.44, jaw: 0.5, smile: 0.36 },
          viseme_lane: :center,
        },
        "Mentor" => {
          position: :left,
          label: "Mentor",
          blendshape_bias: { brow: 0.38, jaw: 0.48, smile: 0.42 },
          viseme_lane: :left,
        },
      }.freeze

      module_function

      def for_persona(persona_id)
        key = persona_id.to_s
        base = PERSONAS[key] || PERSONAS["Pragmatist"]
        expression = Expression.for_council_persona(key)
        viseme_plan = expression.fetch(:viseme_plan, [])

        {
          persona: key,
          voice: CouncilFace.locked_voice,
          position: base[:position],
          label: base[:label],
          blendshapes: Expression.blendshapes_for(:clear).merge(base[:blendshape_bias]),
          viseme_lane: base[:viseme_lane],
          expression:,
          viseme_plan:,
        }
      end

      def voice_for(persona_id)
        for_persona(persona_id)[:voice]
      end
    end
  end
end
