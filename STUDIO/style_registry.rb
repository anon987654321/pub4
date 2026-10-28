# frozen_string_literal: true

require "digest"
require "date"
require "yaml"

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
      style_id version origin_class reference_hashes modality identity_locks
      controlled_variables scope_attributes negative_list temporal_variation deprecation_target
    ].freeze

    class InvalidStyle < ArgumentError; end

    REGISTRY_PATH = File.expand_path("styles/registry.yml", __dir__).freeze

    def self.validate_registry!(document)
      styles = document.fetch("styles")
      raise InvalidStyle, "styles map must not be empty" if styles.empty?

      styles.each do |style_id, definition|
        raise InvalidStyle, "style #{style_id.inspect} must be a map" unless definition.is_a?(Hash)
        if definition["versions"].is_a?(Hash)
          definition["versions"].each do |version, version_body|
            modalities = version_body.is_a?(Hash) ? (version_body["modalities"] || version_body) : nil
            validate_modality_set!(style_id, version, modalities)
          end
        else
          validate_modality_set!(style_id, nil, definition)
        end
      end
      true
    end

    def self.validate_modality_set!(style_id, version, modalities)
      raise InvalidStyle, "style #{style_id} modality set must be a map" unless modalities.is_a?(Hash)
      missing = MODALITIES - modalities.keys.map(&:to_s)
      extra = modalities.keys.map(&:to_s) - MODALITIES
      raise InvalidStyle, "style #{style_id} missing modalities: #{missing.join(', ')}" unless missing.empty?
      raise InvalidStyle, "style #{style_id} has unknown modalities: #{extra.join(', ')}" unless extra.empty?

      MODALITIES.each do |modality|
        entry = modalities[modality] || modalities[modality.to_sym]
        validate!(entry)
        raise InvalidStyle, "style key #{style_id} does not match entry id #{entry['style_id']}" unless entry["style_id"].to_s == style_id.to_s
        raise InvalidStyle, "style #{style_id} modality mismatch for #{modality}" unless entry["modality"].to_s == modality
        if version && entry["version"].to_s != version.to_s
          raise InvalidStyle, "style #{style_id} version key #{version} does not match its entry"
        end
      end
      versions = MODALITIES.map { |modality| (modalities[modality] || modalities[modality.to_sym])["version"].to_s }.uniq
      raise InvalidStyle, "style #{style_id} modalities disagree on version" unless versions.one?
      true
    end

    def self.load_registry(path: REGISTRY_PATH)
      document = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
      raise InvalidStyle, "registry root must be a map" unless document.is_a?(Hash)
      raise InvalidStyle, "registry has no styles map" unless document["styles"].is_a?(Hash)
      validate_registry!(document)

      document
    rescue Psych::Exception => e
      raise InvalidStyle, "registry YAML invalid: #{e.message}"
    end

    def self.resolve(style_id:, modality:, version: nil, registry: nil)
      raise InvalidStyle, "invalid modality #{modality.inspect}" unless MODALITIES.include?(modality.to_s)
      document = registry || load_registry
      style = document.fetch("styles", {}).fetch(style_id.to_s, nil)
      raise InvalidStyle, "unknown style #{style_id.inspect}" unless style.is_a?(Hash)

      # Current registry entries are grouped by modality; histories may be
      # represented under a versions/<semver> key without changing consumers.
      if style["versions"].is_a?(Hash)
        versions = style["versions"]
        selected_version = version || versions.keys.max_by { |value| value.to_s.split(".").map(&:to_i) }
        selected = versions[selected_version.to_s]
        raise InvalidStyle, "unknown style version #{selected_version.inspect}" unless selected.is_a?(Hash)
        modalities = selected["modalities"].is_a?(Hash) ? selected["modalities"] : selected
        entry = modalities[modality.to_s]
      else
        entry = style[modality.to_s]
        if entry.is_a?(Hash) && version && entry["version"].to_s != version.to_s
          raise InvalidStyle, "unknown style version #{version.inspect}"
        end
      end
      raise InvalidStyle, "style #{style_id.inspect} has no #{modality} entry" unless entry.is_a?(Hash)
      validate!(entry)
      entry
    end

    def self.validate!(entry, manifest: nil)
      errors = []
      errors << "entry must be a Hash" unless entry.is_a?(Hash)
      raise InvalidStyle, errors.join("; ") unless errors.empty?

      entry = entry.transform_keys(&:to_s)
      errors.concat(REQUIRED.reject { |key| entry.key?(key) }.map { |key| "missing #{key}" })
      errors << "invalid modality" unless MODALITIES.include?(entry["modality"])
      errors << "invalid origin_class" unless ORIGINS.include?(entry["origin_class"])
      references = entry["reference_hashes"]
      errors << "reference_hashes must be an array" unless references.is_a?(Array)
      if references.is_a?(Array)
        errors << "reference_hashes entries must be SHA-256" unless references.all? { |hash| hash.to_s.match?(/\A[0-9a-f]{64}\z/i) }
        if %w[reference_derived datasheet_derived].include?(entry["origin_class"]) && references.empty?
          errors << "#{entry["origin_class"]} style requires a reference or datasheet hash"
        end
      end
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
          if %w[reference_derived datasheet_derived].include?(entry["origin_class"]) && source.nil?
            errors << "scope #{name} requires its own source fingerprint for #{entry["origin_class"]} styles"
          end
          errors << "scope #{name} strength must be between 0 and 1" unless strength.is_a?(Numeric) && strength.between?(0.0, 1.0)
        end
      end

      deprecation = entry["deprecation_target"]
      unless deprecation.nil?
        begin
          Date.iso8601(deprecation.to_s)
        rescue Date::Error
          errors << "deprecation_target must be an ISO-8601 date or null"
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
      raise InvalidStyle, "new version must increase" unless (new_version <=> old_version) == 1
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
