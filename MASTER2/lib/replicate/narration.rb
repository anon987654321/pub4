# frozen_string_literal: true

module MASTER
  module Replicate
    module Narration
      extend self

      NARRATION_SEGMENTS = [
        {
          id: :intro,
          text: "MASTER2 is a constitutional coding system built for teams that want software to reason before it edits. The central idea is not just faster automation, but safer automation, where every change is treated as a decision with tradeoffs, evidence requirements, and explicit risk boundaries.",
          visual_prompt: "A glowing constitutional document with code flowing through structured gates, transforming from chaotic to organized patterns"
        },
        {
          id: :pipeline,
          text: "At runtime, MASTER2 takes input through a staged path that narrows uncertainty before code is touched. Intake captures the request, guardrails classify risk, routing chooses strategy, adversarial review pressure-tests assumptions, and only then do generation and linting phases produce final output. This model makes the system feel deliberate rather than impulsive.",
          visual_prompt: "A multi-stage funnel pipeline with labeled stages narrowing from wide uncertain input to precise validated output"
        },
        {
          id: :differentiator,
          text: "What makes MASTER2 different is that it combines high-level intent checks with low-level code hygiene. It can enforce structural quality rules, challenge weak reasoning with pressure-pass questioning, and still keep outputs practical for real engineering workflows. The goal is not theatrical intelligence. The goal is dependable edits under pressure.",
          visual_prompt: "Split screen showing high-level architectural diagrams on one side and detailed code inspection on the other, connected by validation lines"
        },
        {
          id: :operations,
          text: "Operationally, the system is designed for long-running use. A single top-level coordinator can be enforced to avoid process chaos, while sub-agents can still parallelize inside bounded tasks where parallelism is useful. This keeps autonomy strong without allowing uncontrolled fan-out.",
          visual_prompt: "A conductor orchestrating parallel worker threads within defined boundaries, shown as controlled branching from a single root"
        },
        {
          id: :interface,
          text: "The interface also reflects this philosophy. The orb-based UI is intentionally low-noise, with visual behavior tied to activity and thinking intensity. It is built to reduce cognitive strain while keeping state readable. Voice and microphone pathways can feed into this loop so interaction remains fluid for non-terminal users.",
          visual_prompt: "A minimalist glowing orb interface pulsing with activity, with subtle voice waveforms flowing in and visual feedback flowing out"
        },
        {
          id: :demo,
          text: "For a practical demonstration, run a refactor workflow on a real target file and show the full cycle from command to output. Highlight where risk is surfaced, where policy intervenes, and how rollback safety is preserved. That sequence communicates both the essence and the engineering details in one continuous story.",
          visual_prompt: "A terminal screen recording showing a refactor command flowing through stages with risk warnings, policy checks, and successful completion"
        },
        {
          id: :closing,
          text: "In short, MASTER2 is about disciplined autonomy: faster delivery, higher confidence, lower entropy.",
          visual_prompt: "Three pillars labeled 'Speed', 'Confidence', and 'Order' supporting a stable platform with the MASTER2 logo"
        }
      ].freeze

      def narration_script
        Result.ok(segments: NARRATION_SEGMENTS)
      end

      def generate_narration(subject: "MASTER2", voice_model: :bark, segments: nil)
        return Result.err("REPLICATE_API_TOKEN not set") unless Replicate.available?

        segments_to_use = segments || NARRATION_SEGMENTS
        return Result.err("No segments provided") if segments_to_use.nil? || segments_to_use.empty?

        results = []
        segments_to_use.each do |segment|
          narration_result = generate_narration_audio(segment[:text], voice_model)
          return narration_result if narration_result.err?

          visual_result = generate_visual(segment[:visual_prompt])
          return visual_result if visual_result.err?

          results << {
            id: segment[:id],
            text: segment[:text],
            audio_url: narration_result.value[:output],
            visual_url: visual_result.value[:urls],
            prompt: segment[:visual_prompt]
          }
        end

        Result.ok(segments: results, subject: subject)
      end

      module_function

      def generate_narration_audio(text, model)
        return Result.err("Text cannot be empty") if text.nil? || text.empty?

        model_id = Replicate.model_id(model)
        Replicate.run(
          model_id: model_id,
          input: { text: text }
        )
      rescue ArgumentError => e
        Result.err("Invalid voice model: #{e.message}")
      end

      def generate_visual(prompt)
        return Result.err("Prompt cannot be empty") if prompt.nil? || prompt.empty?

        Replicate.generate(
          prompt: prompt,
          model: :flux
        )
      end
    end
  end
end
