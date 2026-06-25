# frozen_string_literal: true

module Master
  module Reach
    # Expands terse user seeds into generation-ready prompts, then Strunk-polishes.
    class GenerationPromptRefiner
      PHOTO_SYSTEM = <<~PROMPT.strip
        You write photorealistic image prompts for Flux. The user gives a short seed.

        Expand it into ONE dense paragraph (80–220 words):
        - Subject, environment, time of day, weather, wardrobe/props
        - Lighting (key/fill/rim), lens (focal length), aperture feel, depth of field
        - Composition (rule of thirds, foreground/background layers)
        - Film stock intent (e.g. Kodak Portra, Vision3) and color grade mood
        - Texture: skin, fabric, atmosphere (fog, rain, dust)

        Style rules (Strunk & White / Elements of Style):
        - Active voice, concrete nouns, vivid specific verbs
        - Omit hedges (perhaps, seems, might), preambles, and meta-commentary
        - No bullet lists, no markdown, no quotes, no explanation
        - Do not invent people by name unless the user named them

        Output ONLY the final prompt text.
      PROMPT

      VIDEO_SYSTEM = <<~PROMPT.strip
        You write cinematic text-to-video prompts. The user gives a short seed.

        Expand into ONE dense paragraph (60–180 words):
        - Scene action across 3–5 seconds (what moves, camera motion)
        - Subject, setting, lighting, atmosphere, palette
        - Shot type (wide, medium, dolly, handheld, aerial) and pacing
        - Mood and rhythm — one clear visual idea, not a montage list

        Style rules (Strunk & White / Elements of Style):
        - Active voice, concrete nouns, strong verbs
        - Omit hedges, filler, and meta-commentary
        - No bullet lists, no markdown, no quotes, no explanation

        Output ONLY the final prompt text.
      PROMPT

      VISION_SUFFIX = <<~PROMPT.strip

        A reference image is attached. Match its palette, composition, and subject where relevant.
        Do not describe the image file — fold its visual facts into the prompt.
      PROMPT

      MIN_CHARS = 24

      def self.refine(prompt:, medium:, agent: nil, image: nil)
        new(agent:).refine(prompt:, medium:, image:)
      end

      def initialize(agent: nil)
        @agent = agent
      end

      def refine(prompt:, medium:, image: nil)
        seed = prompt.to_s.strip
        return seed if seed.empty?
        return seed unless @agent

        system = medium.to_sym == :video ? VIDEO_SYSTEM : PHOTO_SYSTEM
        system = "#{system}\n#{VISION_SUFFIX}" if image
        raw = image ? @agent.ask(seed, system: system, image: image) : @agent.ask_once(seed, system: system)
        expanded = normalize_llm_output(raw)
        expanded = seed if expanded.length < MIN_CHARS

        Master::Voice::StrunkPass.call(expanded)
      rescue StandardError
        Master::Voice::StrunkPass.call(seed)
      end

      private

      def normalize_llm_output(raw)
        text = raw.to_s.strip
        text = text.lines.first(6).join(" ").strip if text.include?("\n\n")
        text.gsub(/\A["']|["']\z/, "").strip
      end
    end
  end
end