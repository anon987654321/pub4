# frozen_string_literal: true

require "json"

module STUDIO
  module Replicate
    # Deterministic compiler: structured scene data is authoritative; unknown
    # fields and unresolved references are reported, never silently invented.
    module SceneCompiler
      FIELDS = %w[subject action setting composition lighting palette medium mood].freeze

      def self.compile(scene, vocabulary:, characters: {}, format: :natural)
        scene = scene.transform_keys(&:to_s)
        unknown = scene.keys - FIELDS
        missing = %w[subject].reject { |key| scene[key].to_s.strip != "" }
        unresolved = Array(scene["characters"]).reject { |name| characters.key?(name) || characters.key?(name.to_sym) }
        warnings = []
        warnings << "unknown fields: #{unknown.sort.join(', ')}" unless unknown.empty?
        warnings << "missing required field: subject" unless missing.empty?
        warnings << "unresolved character references: #{unresolved.join(', ')}" unless unresolved.empty?

        values = scene.each_with_object({}) do |(key, value), result|
          next unless FIELDS.include?(key) && !value.to_s.strip.empty?
          terms = value.is_a?(Array) ? value : [value]
          unknown_terms = terms.map(&:to_s).reject { |term| vocabulary.include?(term) }
          warnings << "unresolved vocabulary for #{key}: #{unknown_terms.join(', ')}" unless unknown_terms.empty?
          result[key] = terms.map(&:to_s).select { |term| vocabulary.include?(term) }
        end
        return { status: :rejected, warnings: warnings, scene: values } unless warnings.empty?

        prompt = case format.to_sym
                 when :natural then values.map { |key, items| "#{key}: #{items.join(', ')}" }.join(". ") + "."
                 when :tagged then values.flat_map { |key, items| items.map { |item| "#{key}=#{item}" } }.join(", ")
                 when :json then JSON.generate(values)
                 else
                   return { status: :rejected, warnings: ["unsupported format: #{format}"], scene: values }
                 end
        { status: :ready, scene: values, prompt: prompt, prompt_sha256: Digest::SHA256.hexdigest(prompt) }
      end
    end
  end
end
