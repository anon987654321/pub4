# frozen_string_literal: true

require "json"

module Master
  module Fix
    # The universal transformation algebra is policy, not another detector
    # registry. This object reads its order from data/laws.yml and exposes one
    # validated sequence to fixers, prompts, and tests.
    class TransformationPlan
      Operation = Data.define(:name, :position, :purpose)

      REQUIRED = %w[
        defragment decouple flatten merge split relocate rename reorder remove
        reflow simplify recommend
      ].freeze

      def initialize(root: Master::ROOT, policy: nil)
        @root = root
        @policy = policy || load_policy
        validate!
      end

      def preflight
        Array(@policy.fetch("preflight")).map(&:to_s).freeze
      end

      def operations
        @operations ||= Array(@policy.fetch("order")).each_with_index.map do |name, index|
          Operation.new(
            name: name.to_s,
            position: index + 1,
            purpose: @policy.fetch("principles").fetch(name.to_s),
          )
        end.freeze
      end

      def postflight
        Array(@policy.fetch("postflight")).map(&:to_s).freeze
      end

      def operation(name)
        operations.fetch(index_of(name.to_s))
      rescue IndexError
        raise ArgumentError, "unknown transformation: #{name}"
      end

      def ordered?(names)
        positions = Array(names).map { |name| operation(name).position }
        positions == positions.sort && positions.uniq.length == positions.length
      rescue ArgumentError
        false
      end

      def prompt
        lines = operations.map { |op| format("%2d. %-12s %s", op.position, op.name, op.purpose) }
        [
          "Universal transformation order:",
          *lines,
          "",
          "Preflight: #{preflight.join(", ")}.",
          "Postflight: #{postflight.join(", ")}.",
          "Use the smallest evidenced operation; recommend rather than mutate when proof is insufficient.",
          "Evidence priority: characterization, structural, runtime, and visual evidence outrank semantic judgment; taste alone never authorizes mutation.",
          "Check the domain smell catalog and adapter before proposing a transformation; similarity is not sameness and duplication is not automatically abstraction-worthy.",
        ].join("\n")
      end

      def preservation_contract
        @policy.fetch("preservation").dup.freeze
      end

      def evidence_contract
        @policy.fetch("evidence").dup.freeze
      end

      def comments_policy
        @policy.fetch("comments").dup.freeze
      end

      def rename_policy
        @policy.fetch("rename").dup.freeze
      end

      def modes
        @policy.fetch("modes").dup.freeze
      end

      def refactoring_playbook
        playbook = @policy.fetch("refactoring_playbook")
        {
          "principles" => Array(playbook.fetch("principles")).map { |entry| entry.transform_keys(&:to_s).freeze }.freeze,
          "technique_by_domain" => playbook.fetch("technique_by_domain").transform_keys(&:to_s).transform_values { |values| Array(values).map(&:to_s).freeze }.freeze,
          "gates" => Array(playbook.fetch("gates")).map(&:to_s).freeze,
        }.freeze
      end

      def evidence_hierarchy
        Array(@policy.fetch("evidence_hierarchy")).map { |entry| entry.transform_keys(&:to_s).freeze }.freeze
      end

      def smell_catalog
        @policy.fetch("smell_catalog").transform_keys(&:to_s).transform_values { |values| Array(values).map(&:to_s).freeze }.freeze
      end

      def domain_adapters
        @policy.fetch("domain_adapters").transform_keys(&:to_s).transform_values(&:to_s).freeze
      end

      def automatic_vetoes
        Array(@policy.fetch("automatic_vetoes")).map(&:to_s).freeze
      end

      def research
        Array(@policy.fetch("research")).map { |entry| entry.transform_keys(&:to_s).freeze }.freeze
      end

      def validate!
        pre = preflight
        post = postflight
        order = Array(@policy.fetch("order")).map(&:to_s)
        principles = @policy.fetch("principles")
        raise ArgumentError, "transformation order is empty" if order.empty?

        duplicates = order.tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "duplicate transformations: #{duplicates.join(", ")}" unless duplicates.empty?

        missing = REQUIRED - order
        raise ArgumentError, "missing transformations: #{missing.join(", ")}" unless missing.empty?

        unknown = order - REQUIRED
        raise ArgumentError, "unknown transformations: #{unknown.join(", ")}" unless unknown.empty?

        absent = order.reject { |name| principles.key?(name) }
        raise ArgumentError, "transformation principles missing: #{absent.join(", ")}" unless absent.empty?

        overlap = (pre & order) | (post & order)
        raise ArgumentError, "transformation appears in multiple phases: #{overlap.join(", ")}" unless overlap.empty?

        expected_preservation = %w[semantic_meaning public_contracts reference_graph side_effect_order]
        missing_preservation = expected_preservation - @policy.fetch("preservation").keys.map(&:to_s)
        unless missing_preservation.empty?
          raise ArgumentError, "preservation contract missing: #{missing_preservation.join(", ")}"
        end

        REQUIRED.each { |name| operation_mode_known?(name) }

        validate_playbook!
        validate_evidence!
        validate_smells!
        validate_adapters!
        validate_vetoes!
        validate_research!
        true
      rescue KeyError => e
        raise ArgumentError, "transformation policy missing #{e.key.inspect}"
      end

      private

      def index_of(name)
        operations.index { |operation| operation.name == name.to_s } || raise(ArgumentError, "unknown transformation: #{name}")
      end

      def operation_mode_known?(name)
        modes = @policy.fetch("modes")
        raise ArgumentError, "transformation modes missing" unless modes.is_a?(Hash)
        modes.each_value { |value| raise ArgumentError, "empty transformation mode" if value.to_s.empty? }
        true
      end

      def validate_playbook!
        playbook = refactoring_playbook
        required = %w[characterize_before_change one_hat delete_before_abstract same_reason_to_change preparatory_refactoring history_as_evidence make_deletion_easy domain_first]
        ids = playbook.fetch("principles").map { |entry| entry.fetch("id") }
        missing = required - ids
        raise ArgumentError, "refactoring principles missing: #{missing.join(", ")}" unless missing.empty?
        required_domains = %w[ruby rails prose visual]
        missing_domains = required_domains - playbook.fetch("technique_by_domain").keys
        raise ArgumentError, "refactoring domains missing: #{missing_domains.join(", ")}" unless missing_domains.empty?
        raise ArgumentError, "refactoring gates missing" if playbook.fetch("gates").empty?
        true
      end

      def validate_evidence!
        ids = evidence_hierarchy.map { |entry| entry.fetch("id") }
        raise ArgumentError, "evidence hierarchy is empty" if ids.empty?
        raise ArgumentError, "duplicate evidence level" unless ids.uniq.length == ids.length
        required = %w[characterization structural runtime history visual semantic taste]
        missing = required - ids
        raise ArgumentError, "evidence hierarchy missing: #{missing.join(", ")}" unless missing.empty?
      end

      def validate_smells!
        required = %w[code ruby rails prose visual]
        missing = required - smell_catalog.keys
        raise ArgumentError, "smell catalog missing: #{missing.join(", ")}" unless missing.empty?
        raise ArgumentError, "empty smell catalog" if smell_catalog.values.any?(&:empty?)
      end

      def validate_adapters!
        required = %w[ruby rails prose visual]
        missing = required - domain_adapters.keys
        raise ArgumentError, "domain adapters missing: #{missing.join(", ")}" unless missing.empty?
      end

      def validate_vetoes!
        raise ArgumentError, "automatic vetoes missing" if automatic_vetoes.empty?
      end

      def validate_research!
        raise ArgumentError, "research references missing" if research.empty?
        names = research.map { |entry| entry.fetch("name") }
        required = ["Fowler, Refactoring", "RuboCop Ruby Style Guide", "Clean Code", "Polished Ruby Programming"]
        missing = required - names
        raise ArgumentError, "research references missing: #{missing.join(", ")}" unless missing.empty?
      end

      def load_policy
        return {} unless @root == Master::ROOT

        laws = Master.load_laws(root: @root)
        policy = laws["transformation_policy"]
        return policy if policy.is_a?(Hash)

        path = File.join(@root, "data", "laws.yml")
        sections = laws.is_a?(Hash) ? laws.keys.map(&:to_s).sort : []
        hint = if sections == ["evidence_scoring"]
          "; this looks like the test fixture, not the canonical laws.yml"
        else
          ""
        end
        raise ArgumentError,
          "transformation policy missing from #{path}; available sections: #{sections.join(", ")}#{hint}"
      end
    end
  end
end
