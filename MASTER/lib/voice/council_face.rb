# frozen_string_literal: true

module Master
  module Voice
  # CouncilFace — persona → voice, blendshape bias, spatial lane for council:speech.
    module CouncilFace
      PERSONAS = {
        "Architect" => {
          voice: :pernille,
          position: :left,
          label: "Architect",
          blendshape_bias: { brow: 0.72, jaw: 0.42, lid_open: 0.78 },
          viseme_lane: :left,
        },
        "Skeptic" => {
          voice: :pernille,
          position: :right,
          label: "Skeptic",
          blendshape_bias: { brow: 0.82, jaw: 0.28, lid_open: 0.62 },
          viseme_lane: :right,
        },
        "Pragmatist" => {
          voice: :pernille,
          position: :center,
          label: "Pragmatist",
          blendshape_bias: { brow: 0.48, jaw: 0.55, smile: 0.32 },
          viseme_lane: :center,
        },
        "Security" => {
          voice: :pernille,
          position: :right,
          label: "Security",
          blendshape_bias: { brow: 0.76, jaw: 0.35, lid_open: 0.58 },
          viseme_lane: :right,
        },
        "User" => {
          voice: :pernille,
          position: :center,
          label: "User",
          blendshape_bias: { brow: 0.44, jaw: 0.5, smile: 0.36 },
          viseme_lane: :center,
        },
        "Mentor" => {
          voice: :pernille,
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
        viseme_plan = expression[:viseme_plan] || []

        {
          persona: key,
          voice: base[:voice],
          position: base[:position],
          label: base[:label],
          blendshapes: Expression.blendshapes_for(:clear).merge(base[:blendshape_bias]),
          viseme_lane: base[:viseme_lane],
          expression: expression,
          viseme_plan: viseme_plan,
        }
      end

      def voice_for(persona_id)
        for_persona(persona_id)[:voice]
      end
    end
  end
end
