# frozen_string_literal: true

require "digest"
require "json"

module Studio
  module ReplayManifest
    module_function

    def build(output_path:, prompt:, model:, style: nil, params:, parent_digest: nil, adapter: nil, postpro_chain: [])
      raise ArgumentError, "output file is missing" unless File.file?(output_path)
      origin = value(style, :origin_class)
      lineage = value(style, :lineage) || (style && {
        origin_class: origin,
        reference_hashes: value(style, :reference_hashes) || [],
        registry_entry: value(style, :style_id),
      })
      influence = value(style, :influence) || (style && {
        metric: nil, value: nil,
        reason: "style contract is declarative; output influence was not measured"
      })
      {
        schema_version: 1,
        output_sha256: Digest::SHA256.file(output_path).hexdigest,
        prompt_sha256: Digest::SHA256.hexdigest(prompt.to_s),
        parent_manifest_sha256: parent_digest,
        style_id: value(style, :style_id),
        style_version: value(style, :version),
        modality: value(style, :modality),
        temporal_schedule_hash: temporal_schedule_hash(style),
        model_id: value(model, :id),
        model_version: value(model, :version),
        model_hash: value(model, :hash),
        adapter_id: value(adapter, :id),
        adapter_hash: value(adapter, :hash),
        parameters: params,
        postpro_chain:,
        lineage:,
        influence:,
      }
    end

    def value(hash, key)
      return unless hash.is_a?(Hash)
      hash.key?(key) ? hash[key] : hash[key.to_s]
    end
    private_class_method :value

    def temporal_schedule_hash(style)
      variation = value(style, :temporal_variation)
      return unless variation.is_a?(Hash)

      value(variation, :schedule_hash)
    end
    private_class_method :temporal_schedule_hash

    def digest(manifest)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(manifest)))
    end

    def verify_output!(manifest, output_path:)
      raise ArgumentError, "replay manifest must be a map" unless manifest.is_a?(Hash)

      expected = value(manifest, :output_sha256)
      raise ArgumentError, "replay manifest output hash is missing or malformed" unless
        expected.is_a?(String) && expected.match?(/\A[a-f0-9]{64}\z/)

      actual = Digest::SHA256.file(output_path).hexdigest
      raise ArgumentError, "output hash mismatch" unless actual == expected
      true
    end

    def replayable?(manifest, registry)
      style_id = value(manifest, :style_id)
      version = value(manifest, :style_version)
      modality = value(manifest, :modality)
      return false if style_id.to_s.empty? || version.to_s.empty?
      return false unless registry.is_a?(Hash)

      styles = registry["styles"] || registry[:styles] || registry
      return false unless styles.is_a?(Hash)
      style = styles[style_id.to_s] || styles[style_id.to_s.to_sym]
      return false unless style.is_a?(Hash)

      versioned = style["versions"] || style[:versions]
      modalities = if versioned.is_a?(Hash)
                     selected = versioned[version.to_s] || versioned[version.to_sym]
                     return false unless selected.is_a?(Hash)
                     selected["modalities"] || selected[:modalities] || selected
                   else
                     style
                   end
      return false unless modalities.is_a?(Hash)

      entry = if modality
                modalities[modality.to_s] || modalities[modality.to_sym]
              else
                modalities.values.find do |candidate|
                  candidate.is_a?(Hash) && value(candidate, :version).to_s == version.to_s
                end
              end
      return false unless entry.is_a?(Hash) && value(entry, :version).to_s == version.to_s

      temporal = value(entry, :temporal_variation)
      manifest_schedule = value(manifest, :temporal_schedule_hash)
      if temporal.is_a?(Hash)
        expected_schedule = value(temporal, :schedule_hash)
        return false unless expected_schedule.to_s.match?(/\A[0-9a-f]{64}\z/i)
        return false unless manifest_schedule == expected_schedule
      else
        return false unless temporal == "none"
        return false unless manifest_schedule.nil? || manifest_schedule.to_s.empty?
      end

      true
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(value[key])] }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end
    private_class_method :canonicalize
  end
end
