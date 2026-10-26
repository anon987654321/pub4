# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Validates the governing YAML by its invariants, not by refusing its path.
    # The same check is used by automatic writes and the Claude edit hook through
    # WriteGuard, so editing the constitution does not require a side door.
    module ConfigurationGuard
      module_function

      LAW_MODALITIES = %w[lexical semantic visual].freeze
      REQUIRED_LAW_SECTIONS = %w[
        CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY
        PROXIMITY ABSTRACTION DENSITY RENDERED_VALUES INTER_MODEL_CONTRACT
        veto_patterns law_map transformation_policy law_catalogue
      ].freeze
      REQUIRED_SACRED_PATHS = %w[
        data/SOUL.md data/project_context.yml lib/ground/pledge.rb bin/cli
      ].freeze
      FORBIDDEN_SACRED_PATHS = %w[
        data/ data data/soul.yml data/laws.yml lib/review/scan/
      ].freeze

      def validate(path:, content:)
        kind = kind_for(path)
        return unless kind

        data = YAML.safe_load(content, aliases: true)
        raise ArgumentError, "top-level YAML value must be a mapping" unless data.is_a?(Hash)

        kind == :laws ? validate_laws(data, path:, text: content) : validate_soul(data)
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

      def validate_soul(data)
        absolute = data.fetch("absolute") { raise KeyError, "absolute section is required" }
        raise ArgumentError, "absolute section must be a mapping" unless absolute.is_a?(Hash)
        unless absolute["golden_law"] == "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          raise ArgumentError, "golden_law must remain PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end

        paths = Array(absolute["sacred_paths"]).map { |entry| normalize_path(entry) }
        raise ArgumentError, "sacred_paths must not be empty" if paths.empty?
        forbidden = paths.select { |entry| FORBIDDEN_SACRED_PATHS.include?(entry) }
        unless forbidden.empty?
          raise ArgumentError, "configuration files and retired scanner paths must remain editable: #{forbidden.join(', ')}"
        end

        missing = REQUIRED_SACRED_PATHS - paths
        raise ArgumentError, "critical path protections missing: #{missing.join(', ')}" unless missing.empty?
      end

      def validate_laws(data, path:, text:)
        missing_sections = REQUIRED_LAW_SECTIONS - data.keys.map(&:to_s)
        raise ArgumentError, "required Law sections missing: #{missing_sections.join(', ')}" unless missing_sections.empty?

        catalogue = data.fetch("law_catalogue")
        raise ArgumentError, "law_catalogue must be a mapping" unless catalogue.is_a?(Hash)
        modalities = Array(catalogue["modalities"]).map(&:to_s).uniq.sort
        unless modalities == LAW_MODALITIES
          raise ArgumentError, "law_catalogue.modalities must be #{LAW_MODALITIES.join(', ')}"
        end
        surfaces = Array(catalogue["surfaces"]).map(&:to_s).uniq
        raise ArgumentError, "law_catalogue.surfaces must be non-empty" if surfaces.empty?

        entries = catalogue.fetch("entries") { raise KeyError, "law_catalogue.entries is required" }
        raise ArgumentError, "law_catalogue.entries must be a non-empty mapping" unless entries.is_a?(Hash) && !entries.empty?

        keys = entries.keys.map { |id| id.to_s.downcase }
        duplicates = keys.tally.select { |_id, count| count > 1 }.keys
        raise ArgumentError, "duplicate Law identities: #{duplicates.join(', ')}" unless duplicates.empty?

        repo_root = repository_root(path)
        entries.each do |id, row|
          raise ArgumentError, "Law #{id} must be a mapping" unless row.is_a?(Hash)
          raise ArgumentError, "Law #{id} must be universal" unless row["universal"] == true
          row_modalities = Array(row["modalities"]).map(&:to_s).uniq.sort
          unless row_modalities == LAW_MODALITIES
            raise ArgumentError, "Law #{id} modalities must be #{LAW_MODALITIES.join(', ')}"
          end

          sources = (Array(row["definition_sources"]) + Array(row["detector_sources"])).map(&:to_s).uniq
          raise ArgumentError, "Law #{id} must name a Ruby source" if sources.empty?
          sources.each do |source|
            unless source.start_with?("MASTER/law/") && source.end_with?(".rb") &&
                   !source.split("/").include?("..")
              raise ArgumentError, "Law #{id} has invalid source path #{source.inspect}"
            end

            full_path = File.expand_path(source, repo_root)
            unless full_path.start_with?(repo_root + File::SEPARATOR) && File.file?(full_path)
              raise ArgumentError, "Law #{id} source is missing: #{source}"
            end
          end
        end

        validate_catalogue_key_duplicates(text, entries.keys)
      end

      def validate_catalogue_key_duplicates(text, ids)
        catalogue_start = text.index(/^law_catalogue:\s*$/)
        entries_start = text.index(/^  entries:\s*$/, catalogue_start || 0)
        raise ArgumentError, "law_catalogue.entries source section is missing" unless catalogue_start && entries_start

        tail = text[entries_start..]
        declared = tail.lines.filter_map do |line|
          match = line.match(/\A    ([A-Za-z0-9_]+):\s*\z/)
          match && match[1].downcase
        end
        expected = ids.map { |id| id.to_s.downcase }.sort
        actual = declared.sort
        raise ArgumentError, "Law catalogue keys are duplicated or malformed in YAML source" unless actual == expected
      end

      def normalize_path(value)
        path = value.to_s.tr("\\", "/").strip
        raise ArgumentError, "sacred path must be non-empty" if path.empty?
        raise ArgumentError, "sacred path must be relative: #{path}" if path.start_with?("/") || path.match?(/\A[A-Za-z]:/)
        raise ArgumentError, "sacred path escapes its root: #{path}" if path.split("/").include?("..")

        path
      end

      def repository_root(path)
        expanded = File.expand_path(path.to_s)
        master_root = File.dirname(File.dirname(expanded))
        File.dirname(master_root)
      end
    end
  end
end
