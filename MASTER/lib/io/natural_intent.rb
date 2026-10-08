# frozen_string_literal: true

require "yaml"

module Master
  module Io
    # Declarative natural-language intent and entity extraction.
    #
    # Recognition vocabulary lives in data/patterns.yml. This class supplies the
    # reusable mechanics: normalization, phrase matching, lightweight scoring
    # and entity extraction. It deliberately does not decide what a tool may do.
    module NaturalIntent
      module_function

      Result = Data.define(:intent, :confidence, :entities)

      def resolve(text, domain: :media)
        message = normalize(text)
        specs = patterns.fetch(domain.to_s, {})
        candidates = specs.filter_map do |name, spec|
          score, evidence = score_candidate(message, spec)
          next unless score

          [name.to_sym, score, extract_entities(message, spec), evidence]
        end

        best = candidates.max_by { |candidate| [candidate[1], candidate[3]] }
        return unless best

        Result.new(intent: best[0], confidence: best[1], entities: best[2].freeze)
      rescue StandardError => e
        if defined?(Master::Ground::Swallow)
          Master::Ground::Swallow.log(e, context: "NaturalIntent.resolve")
        end
        nil
      end

      def patterns
        path = File.expand_path("../../data/patterns.yml", __dir__)
        YAML.safe_load_file(path) || {}
      end

      def normalize(text)
        text.to_s
            .unicode_normalize(:nfkc)
            .tr("\u2018\u2019", "\u0027\u0027")
            .tr("\u201c\u201d", "\u0022\u0022")
            .tr("\u2013\u2014", "--")
            .gsub(/\s+/, " ")
            .strip
            .downcase
      end

      def score_candidate(message, spec)
        aliases = Array(spec["aliases"])
        actions = Array(spec["actions"])
        objects = Array(spec["objects"])
        alias_hits = phrase_hits(message, aliases)
        action_hits = phrase_hits(message, actions)
        object_hits = phrase_hits(message, objects)

        return [nil, 0] if alias_hits.empty? && !(action_hits.any? && object_hits.any?)
        return [nil, 0] if alias_hits.any? && action_hits.empty? && object_hits.empty?

        score = 0.0
        score += [0.72 + 0.06 * (alias_hits.length - 1), 0.90].min unless alias_hits.empty?
        score += [0.14, 0.28].min if action_hits.any?
        score += [0.14, 0.28].min if object_hits.any?
        confidence = score.clamp(0.0, 0.99)
        [confidence, alias_hits.length + action_hits.length + object_hits.length]
      end

      def extract_entities(message, spec)
        {
          action: first_hit(message, spec["actions"]),
          object: canonical_or_first_hit(message, spec["objects"]),
          recency: canonical_hit(message, spec["recency"]),
          count: quantity(message, spec["quantities"], spec["objects"], spec["recency"]),
          location: canonical_hit(message, spec["locations"]),
          file_type: canonical_hit(message, spec["file_types"]),
          preset: canonical_hit(message, spec["presets"]),
          path: path(message),
        }.compact
      end

      def phrase_hits(message, values)
        Array(values).map(&:to_s).sort_by { |value| -value.length }.select do |value|
          !value.empty? && boundary_pattern(value).match?(message)
        end
      end

      def first_hit(message, values)
        phrase_hits(message, values).first
      end

      def canonical_or_first_hit(message, values)
        return first_hit(message, values) unless values.is_a?(Hash)

        canonical_hit(message, values)
      end

      def canonical_hit(message, table)
        return unless table.is_a?(Hash)

        table.each do |canonical, aliases|
          return canonical.to_s if phrase_hits(message, aliases).any?
        end
        nil
      end

      def quantity(message, table, objects, recency)
        return unless table.is_a?(Hash)

        object_terms = phrase_terms(objects)
        recency_terms = phrase_terms(recency)
        context = (object_terms + recency_terms).sort_by { |term| -term.length }.join("|")
        number = message.match(/\b(\d+)\s+(?:(?:latest|newest|most\s+recent|recent)\s+)?(?:#{context})\b/i)&.captures&.first
        number ||= message.match(/(?:#{recency_terms.join("|")})\s+(\d+)\b/i)&.captures&.first unless recency_terms.empty?
        return number.to_i if number

        table.each do |canonical, aliases|
          return canonical.to_i if phrase_hits(message, aliases).any?
        end
        nil
      end

      def phrase_terms(value)
        return [] if value.nil?
        return value.flat_map { |key, aliases| [key, *Array(aliases)] } if value.is_a?(Hash)

        Array(value)
      end

      def path(message)
        quoted = message.match(/\b(?:in|at|from|under|over|on|for)\s+["']([^"']+)["']/i)
        return quoted[1] if quoted

        token = message.match(%r{\b(?:in|at|from|under|over|on)\s+(~?(?:/|\./|\.\./)?[^\s"']+/?)(?:\s|$)}i)
        token && token[1]
      end

      def boundary_pattern(value)
        escaped = Regexp.escape(value.to_s.downcase).gsub("\\ ", "\\s+")
        /(?<![[:alnum:]_])#{escaped}(?![[:alnum:]_])/i
      end

      private_class_method :score_candidate, :extract_entities, :phrase_hits, :first_hit,
                           :canonical_hit, :quantity, :path, :boundary_pattern, :patterns, :phrase_terms
    end
  end
end
