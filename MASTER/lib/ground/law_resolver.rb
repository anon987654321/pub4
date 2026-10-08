# frozen_string_literal: true

module Master
  module Ground
    # Resolves Law conflicts and applicability using the constitutional entries
    # in laws.yml (lower priority number wins).
    class LawResolver
      def initialize(laws_data: nil)
        data = laws_data || Master.load_yaml(Master::LAWS_PATH)
        @laws = law_entries(data)
          .transform_keys(&:to_s)
          .transform_values { |value| value["priority"].to_i }
          .sort_by { |_, priority| priority }
          .to_h
      end

      def law_for(law_id, laws_index: nil)
        entry = laws_index&.dig(law_id.to_s.upcase) || laws_index&.dig(law_id.to_s)
        return unless entry

        tags = Array(entry["violates_law"] || entry["supports_law"] || infer_law(entry))
        tags.first
      end

      def winner(law_a, law_b, laws_index: nil)
        priority_a = priority(law_for(law_a, laws_index:))
        priority_b = priority(law_for(law_b, laws_index:))
        return law_a if priority_a < priority_b
        return law_b if priority_b < priority_a

        law_a
      end

      def priority(law_name)
        @laws.fetch(law_name.to_s.upcase, 99)
      end

      def governing_law_ids
        @laws.keys
      end

      def governing_laws
        @laws.dup
      end

      private

      def law_entries(data)
        wrapped = data["laws"]
        return wrapped if wrapped.is_a?(Hash)

        data.select do |name, value|
          name.to_s.match?(/\A[A-Z][A-Z0-9_]*\z/) &&
            value.is_a?(Hash) &&
            value["priority"] &&
            (value["statement"] || value["name"])
        end
      end

      def infer_law(entry)
        tier = entry["tier"].to_s
        case tier
        when "kernel", "safety", "reliability", "performance", "security", "robustness",
             "correctness", "verification" then "ROBUSTNESS"
        when "clean_code", "style", "density", "clarity", "aesthetic" then "DENSITY"
        when "architecture", "design", "solid", "interface" then "ABSTRACTION"
        else "DENSITY"
        end
      end
    end

    # One resolver answers which laws govern a proposed target. The governing
    # roots come from laws.yml; executable Laws are selected by the same
    # language/path applicability contract the scanner uses. The law_map is
    # returned as trace data, not as a second authority.
    class ApplicableLaws
      Selection = Data.define(
        :path, :language, :governing_ids, :executable_ids, :concepts, :unmapped_executable_ids
      ) do
        def ids = (governing_ids + executable_ids).map(&:to_s).uniq

        def include?(law_id)
          ids.any? { |id| id.casecmp?(law_id.to_s) }
        end

        def complete? = unmapped_executable_ids.empty?

        def to_h
          {
            "path" => path,
            "language" => language,
            "governing_laws" => governing_ids,
            "executable_laws" => executable_ids,
            "law_map_concepts" => concepts.first(32),
            "law_map_concept_count" => concepts.length,
            "unmapped_executable_laws" => unmapped_executable_ids.first(32),
            "unmapped_executable_law_count" => unmapped_executable_ids.length,
            "complete" => complete?
          }
        end
      end

      def initialize(root: Master::ROOT, laws_data: nil, definitions: nil)
        @root = File.expand_path(root)
        @data = laws_data || Master.load_yaml(File.join(@root, "data", "laws.yml"))
        @resolver = LawResolver.new(laws_data: @data)
        @definitions = definitions
      end

      def for(path:)
        relative = relative_path(path)
        language = Master.language_for(path)
        executable = executable_definitions.select do |law|
          next false if law.respond_to?(:enforceable?) && !law.enforceable?
          next false unless law.respond_to?(:applies?)

          law.applies?(relative, language)
        end

        map = law_map_entries
        reverse = Hash.new { |hash, key| hash[key] = [] }
        map.each do |id, entry|
          Array(entry["law_ids"]).each do |law_id|
            reverse[law_id.to_s.upcase] << [id.to_s, entry]
          end
        end

        executable_ids = executable.map { |law| law.id.to_s.upcase }.uniq.sort
        concepts = executable_ids.flat_map do |law_id|
          reverse.fetch(law_id, []).map do |id, entry|
            {
              "id" => id,
              "meaning" => entry["meaning"].to_s,
              "status" => entry["status"].to_s,
              "law_ids" => Array(entry["law_ids"]).map { |value| value.to_s.upcase }
            }
          end
        end.uniq { |entry| entry["id"] }

        unmapped = executable_ids.reject { |law_id| reverse.key?(law_id) }

        Selection.new(
          path: relative,
          language: language,
          governing_ids: @resolver.governing_law_ids,
          executable_ids: executable_ids,
          concepts: concepts.sort_by { |entry| entry["id"] },
          unmapped_executable_ids: unmapped
        )
      end

      private

      def executable_definitions
        return @definitions.values if @definitions.is_a?(Hash)

        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
        ::Law.definitions.values
      end

      def law_map_entries
        entries = @data.dig("law_map", "laws")
        entries.is_a?(Hash) ? entries : {}
      end

      def relative_path(path)
        full = File.expand_path(path.to_s)
        return path.to_s unless full.start_with?("#{@root}#{File::SEPARATOR}")

        full.delete_prefix("#{@root}#{File::SEPARATOR}")
      end
    end
  end
end
