# frozen_string_literal: true

require "yaml"

module Master
  # Validates the governing YAML by its invariants. Who may write it is a
  # separate question soul.yml's sacred_paths answer: no automated writer may,
  # and a person commits it with ordinary git. These invariants judge every
  # candidate either way, so a write that is let through is still a valid one.
  module ConfigurationGuard
    module_function

    LAW_MODALITIES = %w[lexical semantic visual].freeze
    REQUIRED_LAW_SECTIONS = %w[
      CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY
      PROXIMITY ABSTRACTION DENSITY RENDERED_VALUES INTER_MODEL_CONTRACT
      veto_patterns law_map transformation_policy law_catalogue
    ].freeze
    # Sacred means no automated writer may change the path. The whole data/
    # directory cannot be: tokens, state and ratchet ceilings there are written
    # by the runtime every day. Nor can the retired scanner directories, which
    # would freeze scanner code that must evolve.
    TOO_BROAD_SACRED_PATHS = %w[
      data/ data lib/review/scan/ lib/review/scan/laws lib/review/scan/laws/
    ].freeze
    LIVE_SOUL = File.expand_path("../data/soul.yml", __dir__)

    def validate(path:, content:, root: nil)
      absolute = File.expand_path(path.to_s, root || Dir.pwd)
      kind = kind_for(absolute)
      return unless kind

      data = YAML.safe_load(content, aliases: true)
      raise ArgumentError, "top-level YAML value must be a mapping" unless data.is_a?(Hash)

      kind == :laws ? validate_laws(data, path: absolute, text: content) : validate_soul(data, path: absolute)
      nil
    rescue Psych::Exception, ArgumentError, KeyError, TypeError => e
      "configuration invariant failed: #{e.class}: #{e.message}"
    end

    def kind_for(path)
      normalized = File.expand_path(path.to_s).tr("\\", "/")
      return :laws if normalized.match?(%r{/MASTER/data/laws\.yml\z})
      return :soul if normalized.match?(%r{/MASTER/data/soul\.yml\z})

      nil
    end

    def validate_soul(data, path: LIVE_SOUL)
      absolute = data.fetch("absolute") { raise KeyError, "absolute section is required" }
      raise ArgumentError, "absolute section must be a mapping" unless absolute.is_a?(Hash)
      unless absolute["golden_law"] == "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        raise ArgumentError, "golden_law must remain PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end

      validate_sacred_paths(Array(absolute["sacred_paths"]).map { |entry| normalize_path(entry) }, path)
    end

    def validate_sacred_paths(paths, path)
      raise ArgumentError, "sacred_paths must not be empty" if paths.empty?

      broad = paths.select { |entry| TOO_BROAD_SACRED_PATHS.include?(entry) }
      unless broad.empty?
        raise ArgumentError, "runtime-written data and retired scanner paths cannot be sacred: #{broad.join(', ')}"
      end

      missing = live_sacred_paths(path) - paths
      raise ArgumentError, "critical path protections missing: #{missing.join(', ')}" unless missing.empty?
    end

    # soul.yml is the one list. A candidate keeps every path the soul it replaces
    # declares, so no validated write can drop a protection; a person removes one
    # with an ordinary commit. A candidate for a file not yet written is held to
    # this MASTER's soul.
    def live_sacred_paths(path)
      soul = YAML.safe_load_file(File.file?(path) ? path : LIVE_SOUL, aliases: true)
      declared = soul.is_a?(Hash) && soul["absolute"].is_a?(Hash) ? soul["absolute"]["sacred_paths"] : nil

      Array(declared).map { |entry| normalize_path(entry) }
    end

    def validate_laws(data, path:, text:)
      validate_required_law_sections(data)
      catalogue = data.fetch("law_catalogue")
      validate_catalogue_contract(catalogue)
      entries = catalogue.fetch("entries")
      validate_catalogue_entries(entries, repository_root(path))
      validate_catalogue_key_duplicates(text, entries.keys)
    end

    def validate_required_law_sections(data)
      missing = REQUIRED_LAW_SECTIONS - data.keys.map(&:to_s)
      raise ArgumentError, "required Law sections missing: #{missing.join(', ')}" unless missing.empty?
    end

    def validate_catalogue_contract(catalogue)
      raise ArgumentError, "law_catalogue must be a mapping" unless catalogue.is_a?(Hash)
      modalities = Array(catalogue["modalities"]).map(&:to_s).uniq.sort
      raise ArgumentError, "law_catalogue.modalities must be #{LAW_MODALITIES.join(', ')}" unless modalities == LAW_MODALITIES
      raise ArgumentError, "law_catalogue.surfaces must be non-empty" if Array(catalogue["surfaces"]).empty?
      entries = catalogue.fetch("entries") { raise KeyError, "law_catalogue.entries is required" }
      raise ArgumentError, "law_catalogue.entries must be a non-empty mapping" unless entries.is_a?(Hash) && !entries.empty?

      keys = entries.keys.map { |id| id.to_s.downcase }
      duplicates = keys.tally.select { |_id, count| count > 1 }.keys
      raise ArgumentError, "duplicate Law identities: #{duplicates.join(', ')}" unless duplicates.empty?
    end

    def validate_catalogue_entries(entries, repo_root)
      entries.each do |id, row|
        raise ArgumentError, "Law #{id} must be a mapping" unless row.is_a?(Hash)
        raise ArgumentError, "Law #{id} must be universal" unless row["universal"] == true
        modalities = Array(row["modalities"]).map(&:to_s).uniq.sort
        raise ArgumentError, "Law #{id} modalities must be #{LAW_MODALITIES.join(', ')}" unless modalities == LAW_MODALITIES

        validate_catalogue_sources(id, row)
      end
    end

    def validate_catalogue_sources(id, row)
      sources = (Array(row["definition_sources"]) + Array(row["detector_sources"])).map(&:to_s).uniq
      raise ArgumentError, "Law #{id} must name a Ruby source" if sources.empty?
      sources.each { |source| validate_catalogue_source(id, source) }
    end

    # Path syntax belongs in per-write admission. File existence belongs in the
    # whole-tree LawRegistryAudit, because one transaction may add/move the file
    # and update the catalogue in either write order.
    def validate_catalogue_source(id, source)
      valid = source.start_with?("MASTER/law/") && source.end_with?(".rb") &&
              !source.split("/").include?("..")
      raise ArgumentError, "Law #{id} has invalid source path #{source.inspect}" unless valid
    end

    def validate_catalogue_key_duplicates(text, ids)
      catalogue_start = text.index(/^law_catalogue:\s*$/)
      entries_start = text.index(/^  entries:\s*$/, catalogue_start || 0)
      raise ArgumentError, "law_catalogue.entries source section is missing" unless catalogue_start && entries_start

      declared = text[entries_start..].lines.filter_map do |line|
        match = line.match(/\A    ([A-Za-z0-9_]+):\s*\z/)
        match && match[1].downcase
      end
      expected = ids.map { |id| id.to_s.downcase }.sort
      raise ArgumentError, "Law catalogue keys are duplicated or malformed in YAML source" unless declared.sort == expected
    end

    def normalize_path(value)
      path = value.to_s.tr("\\", "/").strip
      raise ArgumentError, "sacred path must be non-empty" if path.empty?
      raise ArgumentError, "sacred path must be relative: #{path}" if path.start_with?("/") || path.match?(/\A[A-Za-z]:/)
      raise ArgumentError, "sacred path escapes its root: #{path}" if path.split("/").include?("..")

      path
    end

    def repository_root(path)
      master_root = File.dirname(File.dirname(File.expand_path(path)))
      File.dirname(master_root)
    end
  end
end
