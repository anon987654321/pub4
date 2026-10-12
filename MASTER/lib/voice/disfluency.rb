# frozen_string_literal: true

require "digest"

module Master
  module Voice
    # Small speech-only false starts and fillers. The transcript and model output
    # stay untouched: this runs after speakable text has been prepared and before
    # synthesis. It is deliberately bounded and skips lists, code, URLs and paths.
    module Disfluency
      DEFAULTS = {
        "enabled" => true,
        "probability" => 0.20,
        "min_words" => 6,
        "stutter_probability" => 0.35,
        "fillers" => %w[um uh],
        "seed" => "master-vocal-character-v1",
      }.freeze

      FIRST_WORD = /\A(?<word>I|I'm|I've|I'll|I'd|we|we're|we've|we'll|you|you're|that|it)(?<rest>\s+.+)\z/i
      HEDGED_START = /\A(?<subject>I|I'm|I've|I'll|I'd|we|we're|you|you're)(?<space>\s+)(?<thought>think|guess|wonder|hope|feel|am not sure|don't know|do not know)\b(?<rest>.*)\z/i
      TECHNICAL = %r{(?:https?://|\b(?:[\w.-]+/){1,}[\w.-]+\b|\b[A-Za-z_][A-Za-z0-9_]*\.(?:rb|yml|yaml|json|js|ts|css|scss|html|sh)\b|\b(?:bundle exec|git (?:commit|push|pull|status)|ssh\s|curl\s|rails\s|rake\s|ruby\s)\b)}i

      module_function

      # Returns the spoken variant, or the original string when the policy does
      # not admit a safe conversational imperfection. Seeded output is stable for
      # a given sentence, so caches and retries do not produce different words.
      def apply(text, source: text, seed: nil)
        spoken = text.to_s
        return spoken if spoken.strip.empty?

        cfg = DEFAULTS.merge(Policy.data.fetch("disfluencies", {}).to_h.transform_keys(&:to_s))
        override = ENV["MASTER_TTS_DISFLUENCIES"].to_s.strip.downcase
        return spoken if override == "0" || %w[off false no].include?(override)
        return spoken if override.empty? && cfg["enabled"] != true
        return spoken unless eligible?(spoken, source, cfg)

        identity = [seed || ENV["MASTER_TTS_SEED"], cfg["seed"], spoken].compact.join("\0")
        number = Digest::SHA256.hexdigest(identity)[0, 16].to_i(16)
        random = Random.new(number)
        return spoken if random.rand >= cfg.fetch("probability", 0.20).to_f.clamp(0.0, 1.0)

        fillers = Array(cfg["fillers"]).map(&:to_s).map(&:strip).reject(&:empty?)
        fillers = DEFAULTS["fillers"] if fillers.empty?
        if random.rand < cfg.fetch("stutter_probability", 0.35).to_f.clamp(0.0, 1.0)
          stutter(spoken) || hesitation(spoken, fillers, random) || prefix(spoken, fillers, random)
        else
          hesitation(spoken, fillers, random) || prefix(spoken, fillers, random)
        end
      rescue StandardError
        # An optional delivery layer must never take a working voice offline.
        text.to_s
      end

      def eligible?(spoken, source, cfg)
        raw = source.to_s
        return false if raw.include?("`") || raw.match?(/https?:\/\//i)
        return false if raw.lines.any? { |line| line.match?(/\A\s*(?:[-*•●▪◦]|\d+[.)])\s+/) }
        return false if raw.match?(TECHNICAL)
        return false if spoken.match?(/\A\s*(?:https?:\/\/|\{\s*["']|\[\s*\{)/)

        words = spoken.scan(/[\p{L}\p{N}]+(?:['’][\p{L}]+)*/u)
        return false if words.size < cfg.fetch("min_words", 6).to_i

        # Keep the ticks within personal/conversational language. Don't make a
        # status report, instruction or diagnosis sound unsure just to add colour.
        spoken.match?(/\b(?:I|I'm|I've|I'll|I'd|we|we're|we've|we'll|you|you're|think|guess|wonder|hope|feel|maybe|perhaps|not sure|don't know|sorry|glad|honestly|I mean)\b/i)
      end

      def stutter(text)
        match = text.match(FIRST_WORD)
        return unless match

        word = match[:word]
        "#{word}- #{word}#{match[:rest]}"
      end

      def hesitation(text, fillers, random)
        match = text.match(HEDGED_START)
        return unless match

        filler = fillers[random.rand(fillers.size)]
        "#{match[:subject]}, #{filler}, #{match[:thought]}#{match[:rest]}"
      end

      def prefix(text, fillers, random)
        filler = fillers[random.rand(fillers.size)]
        "#{filler.capitalize}, #{text}"
      end
    end
  end
end
