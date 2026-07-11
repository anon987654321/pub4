# frozen_string_literal: true

require "yaml"

module Master
  module Voice
    # MASTER's behavioral persona: voice, TTS settings, and LLM style.
    class Personality
      include PersonalityPromptBuilder

      DEFAULT = :malay
      AXIOM_DISPLAY_LIMIT = 10

      FALLBACK_PERSONA = {
        "voice" => "ms-MY-OsmanNeural",
        # Kept in sync with data/personas.yml's malay entry — see its comment
        # for why -35%/-150Hz was replaced (well past the range Azure/edge
        # neural voices render cleanly).
        "tts_rate" => "-8%",
        "tts_pitch" => "-35Hz",
        "style" => "deep",
        "description" => "Terse. Direct. No filler. Dark.",
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

      def system_prompt
        @system_prompt ||= build_system_prompt
      end

      def browser_profile
        {
          name: @name.to_s,
          voice: @voice,
          tts_rate: @tts_rate,
          tts_pitch: @tts_pitch,
          style: @style,
          description: @description,
          knowledge_sources: @knowledge_sources,
          disclaimer: @disclaimer,
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

      def load_identity
        data_path = File.join(Master::ROOT, "data", "IDENTITY.md")
        return File.read(data_path, encoding: "UTF-8").strip if File.exist?(data_path)

        legacy = File.join(Master::ROOT, "IDENTITY.md")
        return File.read(legacy, encoding: "UTF-8").strip if File.exist?(legacy)

        ""
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "personality.load_identity", path:)
        ""
      end

      def persona_knowledge_sources
        return if @knowledge_sources.empty?

        lines = @knowledge_sources.map { |source| "- #{source}" }
        ["<master_knowledge_sources>", *lines, "</master_knowledge_sources>"].join("\n")
      end
    end
  end
end
