# frozen_string_literal: true

require "digest"
require "date"

module Studio
  # Validates immutable, modality-specific style contracts before an adapter
  # may propose parameters to a deterministic renderer.
  module StyleRegistry
    MODALITIES = %w[image prompt audio].freeze
    ORIGINS = %w[hand_authored reference_derived datasheet_derived learned].freeze
    ATTRIBUTE_CLASSES = %w[
      colour texture_grain structure_composition timbre_instrumentation
      groove_rhythm harmonic_vocabulary tone_curve
    ].freeze
    REQUIRED = %w[
      style_id version origin_class modality identity_locks controlled_variables
      scope_attributes negative_list temporal_variation
    ].freeze

    class InvalidStyle < ArgumentError; end

    def self.validate!(entry, manifest: nil)
      errors = []
      errors << "entry must be a Hash" unless entry.is_a?(Hash)
      raise InvalidStyle, errors.join("; ") unless errors.empty?

      entry = entry.transform_keys(&:to_s)
      errors.concat(REQUIRED.reject { |key| entry.key?(key) }.map { |key| "missing #{key}" })
      errors << "invalid modality" unless MODALITIES.include?(entry["modality"])
      errors << "invalid origin_class" unless ORIGINS.include?(entry["origin_class"])
      errors << "invalid semver version" unless entry["version"].to_s.match?(/\A\d+\.\d+\.\d+\z/)
      errors << "style_id must be non-empty" if entry["style_id"].to_s.strip.empty?
      errors << "identity_locks must be an array" unless entry["identity_locks"].is_a?(Array)
      errors << "controlled_variables must be an array" unless entry["controlled_variables"].is_a?(Array)
      errors << "negative_list must be an array" unless entry["negative_list"].is_a?(Array)

      scope = entry["scope_attributes"]
      unless scope.is_a?(Hash)
        errors << "scope_attributes must be a map"
      else
        scope.each do |name, declaration|
          errors << "unknown scope class #{name}" unless ATTRIBUTE_CLASSES.include?(name.to_s)
          unless declaration.is_a?(Hash)
            errors << "scope #{name} must declare source and strength"
            next
          end
          declaration = declaration.transform_keys(&:to_s)
          source = declaration["source"]
          strength = declaration["strength"]
          errors << "scope #{name} source must be SHA-256 or null" unless source.nil? || source.to_s.match?(/\A[0-9a-f]{64}\z/i)
          errors << "scope #{name} strength must be between 0 and 1" unless strength.is_a?(Numeric) && strength.between?(0.0, 1.0)
        end
      end

      variation = entry["temporal_variation"]
      unless variation == "none" || (variation.is_a?(Hash) && variation.transform_keys(&:to_s)["schedule_hash"].to_s.match?(/\A[0-9a-f]{64}\z/i))
        errors << "temporal_variation must be none or declare a SHA-256 schedule_hash"
      end

      if manifest
        manifest = manifest.transform_keys(&:to_s)
        errors << "manifest requires lineage" unless manifest["lineage"].is_a?(Hash)
        influence = manifest["influence"]
        errors << "manifest requires influence block" unless influence.is_a?(Hash)
        if influence.is_a?(Hash) && influence["value"].nil? && influence["reason"].to_s.strip.empty?
          errors << "null influence requires a reason"
        end
        if variation.is_a?(Hash) && manifest["temporal_schedule_hash"] != variation.transform_keys(&:to_s)["schedule_hash"]
          errors << "temporal schedule hash does not match manifest"
        end
        errors << "manifest negative_list_hash mismatch" if manifest["negative_list_hash"] && manifest["negative_list_hash"] != negative_list_hash(entry)
      end

      raise InvalidStyle, errors.join("; ") unless errors.empty?
      true
    end

    def self.negative_list_hash(entry)
      Digest::SHA256.hexdigest(Array(entry.fetch("negative_list")).map(&:to_s).sort.join("\n"))
    end

    # Released entries are write-once. A changed entry is a new version with
    # an explicit predecessor, never an in-place edit.
    def self.validate_mint!(previous:, candidate:, owner:, rationale:)
      validate!(candidate)
      raise InvalidStyle, "owner required" if owner.to_s.strip.empty?
      raise InvalidStyle, "change rationale required" if rationale.to_s.strip.empty?
      old_version = previous.fetch("version").to_s.split(".").map(&:to_i)
      new_version = candidate.fetch("version").to_s.split(".").map(&:to_i)
      raise InvalidStyle, "new version must increase" unless new_version > old_version
      raise InvalidStyle, "style_id cannot change across versions" unless previous.fetch("style_id") == candidate.fetch("style_id")
      true
    end

    # Rejection occurs before rendering; an adapter must supply a real
    # deterministic matcher rather than a placeholder that always accepts.
    def self.refuse!(proposal:, negative_list:, matcher:)
      raise ArgumentError, "matcher must be callable" unless matcher.respond_to?(:call)
      match = Array(negative_list).find { |item| matcher.call(proposal, item) }
      return nil unless match

      { status: :refused, reason: "STYLE_REFUSAL", matched_entry: match }
    end
  end
end
