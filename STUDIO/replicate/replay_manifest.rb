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
        registry_entry: value(style, :style_id)
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
        model_id: value(model, :id),
        model_version: value(model, :version),
        model_hash: value(model, :hash),
        adapter_id: value(adapter, :id),
        adapter_hash: value(adapter, :hash),
        parameters: params,
        postpro_chain: postpro_chain,
        lineage: lineage,
        influence: influence
      }
    end

    def value(hash, key)
      return nil unless hash.is_a?(Hash)
      hash.key?(key) ? hash[key] : hash[key.to_s]
    end
    private_class_method :value

    def digest(manifest)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(manifest)))
    end

    def verify_output!(manifest, output_path:)
      expected = manifest.fetch(:output_sha256)
      actual = Digest::SHA256.file(output_path).hexdigest
      raise ArgumentError, "output hash mismatch" unless actual == expected
      true
    end

    def replayable?(manifest, registry)
      style_id = manifest[:style_id] || manifest["style_id"]
      version = manifest[:style_version] || manifest["style_version"]
      modality = manifest[:modality] || manifest["modality"]
      styles = registry["styles"] || registry[:styles] || registry
      style = styles[style_id.to_s] || styles[style_id.to_sym]
      return false unless style.is_a?(Hash)

      if style["versions"].is_a?(Hash) || style[:versions].is_a?(Hash)
        versions = style["versions"] || style[:versions]
        selected = versions[version.to_s] || versions[version.to_sym]
        return false unless selected.is_a?(Hash)
        modalities = selected["modalities"] || selected[:modalities] || selected
        return modalities.key?(modality.to_s) || modalities.key?(modality.to_sym) if modality
        return modalities.values.any? { |entry| entry.is_a?(Hash) && entry["version"].to_s == version.to_s }
      end

      if modality
        entry = style[modality.to_s] || style[modality.to_sym]
        entry.is_a?(Hash) && entry["version"].to_s == version.to_s
      else
        style.values.any? { |entry| entry.is_a?(Hash) && entry["version"].to_s == version.to_s }
      end
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
