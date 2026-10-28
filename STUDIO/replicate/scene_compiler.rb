# frozen_string_literal: true

require "json"
require "digest"

module STUDIO
  module Replicate
    # Deterministic compiler: structured scene data is authoritative; unknown
    # fields and unresolved references are reported, never silently invented.
    module SceneCompiler
      FIELDS = %w[subject action setting composition lighting palette medium mood characters].freeze

      def self.compile_fields(document, options:, vocabularies:, compiler:)
        doc = document.transform_keys(&:to_s)
        errors = (doc.keys - %w[prompt fields]).map { |key| "unknown scene JSON key: #{key}" }
        prompt = doc["prompt"].to_s.strip
        errors << "scene JSON prompt must be a non-empty string" if prompt.empty?
        fields = doc.fetch("fields", {})
        errors << "scene JSON fields must be an object" unless fields.is_a?(Hash)
        fields = fields.transform_keys(&:to_s) if fields.is_a?(Hash)
        compiled_options = options.dup

        if fields.is_a?(Hash)
          fields.each do |name, value|
            key = name.to_sym
            table = vocabularies[key]
            unless table.is_a?(Hash)
              errors << "unknown vocabulary field: #{name}"
              next
            end
            if value.nil? || value.is_a?(Array) || value.is_a?(Hash)
              errors << "field #{name} must be one vocabulary value"
              next
            end
            normalized = value.to_s.strip.downcase.tr("- ", "__")
            unless table.key?(normalized)
              errors << "unknown #{name} #{value.inspect}; known: #{table.keys.join(', ')}"
              next
            end
            compiled_options[key] = normalized
          end
        end

        return { status: :rejected, warnings: errors } unless errors.empty?
        compiled = compiler.call(prompt, compiled_options)
        {
          status: :ready,
          prompt: prompt,
          fields: fields,
          options: compiled_options,
          compiled_prompt: compiled,
          prompt_sha256: Digest::SHA256.hexdigest(prompt),
          compiled_prompt_sha256: Digest::SHA256.hexdigest(compiled)
        }
      rescue StandardError => e
        { status: :rejected, warnings: [e.message] }
      end

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
          if key == "characters"
            result[key] = Array(value).map { |name| characters[name] || characters[name.to_sym] }
            next
          end
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
