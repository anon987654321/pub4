# frozen_string_literal: true

module Master
  module Ground
    # Resolves Law conflicts and applicability using the constitutional entries
    # in laws.yml (lower priority number wins).
    class LawResolver
      LEGACY_ALIASES = {
        "CAPABILITY_STATUS_MUST_BE_TRUTHFUL" => "TRUTHFUL_STATUS",
        "RENDERED_VALUES" => "OPERATOR_RENDERED",
      }.freeze

      def initialize(laws_data: nil, root: Master::ROOT)
        @root = File.expand_path(Master.master_root(root:))
        data = laws_data || Master.laws_document(root: @root)
        entries = Master.law_entries_in(data || {})
        @entries = entries.to_h { |entry| [entry.fetch("id").to_s.upcase, entry] }
        @precedence_order = Master::Soul.invariant_order(root: @root)
      end

      def law_for(law_id, laws_index: nil)
        entry = laws_index&.dig(law_id.to_s.upcase) || laws_index&.dig(law_id.to_s)
        return unless entry

        tags = Array(entry["violates_law"] || entry["supports_law"] || infer_law(entry))
        tag = tags.first
        LEGACY_ALIASES.fetch(tag.to_s.upcase, tag)
      end

      def winner(law_a, law_b, laws_index: nil)
        node_a = node_for(law_for(law_a, laws_index:) || law_a)
        node_b = node_for(law_for(law_b, laws_index:) || law_b)
        return law_b if node_a.nil? && node_b
        return law_a if node_b.nil? && node_a
        return law_a unless node_a && node_b

        result = Master::Soul.winner(node_a, node_b, root: @root)
        return law_a if result.nil? || result == node_a
        return law_b if result == node_b

        law_a
      end

      def precedence_index(law_name)
        node = node_for(law_name)
        @precedence_order.index(node) || 99
      end

      # Transitional method name for callers not yet migrated. The value is a
      # derived position in laws.yml order, never a declared priority field.
      def priority(law_name) = precedence_index(law_name)

      def governing_law_ids
        @precedence_order.filter_map do |node|
          @entries.find { |_id, entry| entry["node"].to_s == node }&.first
        end
      end

      def governing_laws
        governing_law_ids.each_with_index.to_h
      end

      private

      def node_for(id, seen = {})
        key = LEGACY_ALIASES.fetch(id.to_s.upcase, id.to_s.upcase)
        return key.downcase if @precedence_order.include?(key.downcase)
        return if seen[key]

        seen[key] = true
        entry = @entries[key]
        return unless entry

        node = entry["node"]
        return node.to_s if node

        parent = entry["parent"]
        parent ? node_for(parent, seen) : nil
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
            "complete" => complete?,
          }
        end
      end

      def initialize(root: Master::ROOT, laws_data: nil, definitions: nil)
        @root = File.expand_path(root)
        @data = laws_data || Master.load_laws(root: @root)
        @resolver = LawResolver.new(root: @root)
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
              "law_ids" => Array(entry["law_ids"]).map { |value| value.to_s.upcase },
            }
          end
        end.uniq { |entry| entry["id"] }

        unmapped = executable_ids.reject { |law_id| reverse.key?(law_id) }

        Selection.new(
          path: relative,
          language:,
          governing_ids: @resolver.governing_law_ids,
          executable_ids:,
          concepts: concepts.sort_by { |entry| entry["id"] },
          unmapped_executable_ids: unmapped,
        )
      end

      private

      def executable_definitions
        return @definitions.values if @definitions.is_a?(Hash)

        require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
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
