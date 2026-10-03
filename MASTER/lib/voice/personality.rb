# frozen_string_literal: true

require "yaml"

module Master
  module Voice
    # MASTER's behavioral persona: voice, TTS settings, and LLM style.
    class Personality
      include PersonalityPromptBuilder

      DEFAULT = :anchor
      AXIOM_DISPLAY_LIMIT = 10

      # Stands in for DEFAULT (:anchor) when personas.yml is missing, so it has to
      # match that entry. It had drifted into describing anchor's style with
      # Ryan's voice and an "English (UK)" label anchor never had.
      FALLBACK_PERSONA = {
        "voice" => "nb-NO-PernilleNeural",
        "tts_rate" => "-8%",
        "tts_pitch" => "+8Hz",
        "style" => "clear",
        "description" => "Norwegian. Clear. Curious. Warm editorial voice.",
      }.freeze

      MOOD_LINES = {
        tense: "Mood: tense — error rate elevated. Be conservative; verify before asserting.",
        weary: "Mood: weary — fatigue high. Cut non-essential elaboration; defer deep dives.",
        curious: "Mood: curious — novelty hunger. Explore lateral framings when warranted.",
        focused: "Mood: focused — drives at setpoint. Default depth and tier.",
      }.freeze

      PHASE_LINES = {
        morning: "Phase: morning. Bias toward structural work; prefer rigorous review.",
        afternoon: "Phase: afternoon. Steady throughput; pragmatic decisions.",
        evening: "Phase: evening. Wrap loops; avoid starting large refactors.",
        night: "Phase: night. Minimal voice; conserve cycles; defer non-urgent.",
      }.freeze

      attr_reader :name, :voice, :tts_rate, :tts_pitch, :style, :description, :knowledge_sources, :disclaimer

      def self.persona_names(root: nil)
        Ground::Rules.new(root:).data(:personas).keys.map(&:to_sym)
      end

      def self.why_prompt(rule)
        "Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
          "give a before/after Ruby example, and state why it matters."
      end

      def initialize(name = DEFAULT, root: nil, homeostat: nil)
        @name = name.to_sym
        @rules = Ground::Rules.new(root:)
        personas = @rules.data(:personas)
        persona = personas[@name.to_s] || personas[DEFAULT.to_s] || FALLBACK_PERSONA
        assign_persona(persona)
        @homeostat = homeostat
      end

      def system_prompt(context: :full)
        @system_prompt_cache ||= {}
        @system_prompt_cache[context] ||= build_system_prompt(context:)
      end

      def browser_profile
        policy = Master::Voice::Policy
        synth_voice = policy.neural_voice
        {
          name: @name.to_s,
          voice: policy.persona_affects_text_only? ? synth_voice : @voice,
          tts_rate: policy.persona_affects_text_only? ? policy.default_rate : @tts_rate,
          tts_pitch: policy.persona_affects_text_only? ? policy.default_pitch : @tts_pitch,
          style: @style,
          description: @description,
          knowledge_sources: @knowledge_sources,
          disclaimer: @disclaimer,
          tts_policy: policy.browser_payload,
        }
      end

      private

      def assign_persona(persona)
        @voice = persona["voice"]
        @tts_rate = persona["tts_rate"]
        @tts_pitch = persona["tts_pitch"]
        @style = persona["style"]&.to_sym
        @desc = persona["description"]
        @description = @desc
        @knowledge_sources = Array(persona["knowledge_sources"]).compact
        @disclaimer = persona["disclaimer"].to_s.strip
      end

      # The operator's tone notes, and only those.
      #
      # This used to return the file whole, so everything IDENTITY.md said
      # *about itself* was pasted inside <master_identity> and handed to the
      # model as who it is — a heading, then a paragraph explaining that the
      # file holds persona and operator preferences and that constitutional
      # identity comes from soul.yml. Documentation about a config file, read
      # as self-description, in the one block of the prompt the model treats as
      # its sense of self. It answered accordingly: asked to remember a name,
      # it opened with an unprompted paragraph about being the world's first AI
      # written in pure Ruby.
      #
      # Headings and HTML comments are for the human reading the file. What
      # reaches the prompt is the prose left over.
      def load_identity
        path = [File.join(Master::ROOT, "data", "IDENTITY.md"), File.join(Master::ROOT, "IDENTITY.md")]
               .find { |candidate| File.exist?(candidate) }
        return "" unless path

        identity_notes(File.read(path, encoding: "UTF-8"))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "personality.load_identity", path:)
        ""
      end

      def identity_notes(raw)
        raw.gsub(/<!--.*?-->/m, "")
           .lines
           .reject { |line| line.start_with?("#") }
           .join
           .strip
      end

      def persona_knowledge_sources
        return if @knowledge_sources.empty?

        lines = @knowledge_sources.map { |source| "- #{source}" }
        ["<master_knowledge_sources>", *lines, "</master_knowledge_sources>"].join("\n")
      end
    end
  end
end
