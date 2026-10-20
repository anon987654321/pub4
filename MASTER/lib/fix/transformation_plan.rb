# frozen_string_literal: true

require "json"

module Master
  module Fix
    # The universal transformation algebra is policy, not another detector
    # registry. This object reads its order from data/laws.yml and exposes one
    # validated sequence to fixers, prompts, and tests.
    class TransformationPlan
      Operation = Data.define(:name, :position, :purpose)

      # Membership only; the authoritative order lives in data/laws.yml.
      REQUIRED = %w[
        decouple defragment flatten hoist merge recommend relocate remove rename
        reorder reflow simplify split
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
            purpose: @policy.fetch("operations").fetch(name.to_s),
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
          "Universal transformation policy:",
          *lines,
          "",
          "Preflight: #{preflight.join(", ")}.",
          "Postflight: #{postflight.join(", ")}.",
          "Hard invariants (encoded gates, not suggestions):",
          *invariants.map { |name, value| "  #{name}: #{value}" },
          "",
          "Read-only candidate map: consider at least #{candidate_map_policy.fetch("minimum_alternatives")} materially distinct alternatives and score payoff/risk #{candidate_map_policy.fetch("score_range").inspect}; compare at least #{candidate_map_policy.fetch("minimum_distinct_target_paths")} distinct target paths when they exist. #{candidate_map_policy.fetch("exhaustion")}",
          "",
          "DRY versus KISS, in order:",
          *decision_table.map { |row| "  #{row.fetch("condition")} => #{row.fetch("choose")}" },
          "",
          "Operation trigger and veto:",
          *operation_rules.map { |name, row| "  #{name}: when #{row.fetch("when")} Not when #{row.fetch("not_when")}" },
          "",
          "Loop exit contracts:",
          *loop_policy.map { |state, condition| "  #{state}: #{condition}" },
          "",
          "Scorecard dimensions:",
          "  metrics: #{scorecard_policy.fetch("metrics").join(", ")}",
          "  history window: #{scorecard_policy.fetch("history_window_commits")} commits",
          *scorecard_policy.fetch("measurements").map { |name, method| "  #{name}: #{method}" },
          *scorecard_policy.fetch("acceptance").map { |name, rule| "  accept #{name}: #{rule}" },
          "",
          "Proof of equivalence must attach: #{proof_of_equivalence.fetch("required").join(", ")}.",
          "Narrative alone is not proof: #{proof_of_equivalence.fetch("no_narrative_substitute")}.",
          "Existing structural gates and their bad/good fixtures:",
          *structural_gates.map { |id, row| "  #{id}: #{row.fetch("detector")}; flags #{row.fetch("positive_fixture")}; spares #{row.fetch("negative_fixture")}" },
          *not_applicable_operations.map { |id, why| "  #{id}: not applicable — #{why}" },
          "",
          "Evidence priority: characterization, structural, runtime, and visual evidence outrank semantic judgment; taste alone never authorizes mutation.",
          "Check the domain smell catalog and adapter before proposing a transformation; similarity is not sameness and duplication is not automatically abstraction-worthy.",
          research_instructions,
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
          "methods" => Array(playbook.fetch("methods")).map { |entry| entry.transform_keys(&:to_s).freeze }.freeze,
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

      def invariants = policy_section("invariants")
      def candidate_map_policy = policy_section("candidate_map")
      def loop_policy = policy_section("loop")
      def operation_rules = policy_section("operation_rules")
      def decision_table = policy_section("decision_table")
      def scorecard_policy = policy_section("scorecard")
      def proof_of_equivalence = policy_section("proof_of_equivalence")
      def structural_gates = policy_section("structural_gates")
      def not_applicable_operations = policy_section("not_applicable_operations")

      def research
        Array(@policy.fetch("research")).map { |entry| entry.transform_keys(&:to_s).freeze }.freeze
      end

      def research_protocol
        @policy.fetch("research_protocol").transform_keys(&:to_s)
      end

      def research_instructions
        Array(research_protocol.fetch("instructions")).map(&:to_s).join("\n")
      end

      def validate!
        pre = preflight
        post = postflight
        order = Array(@policy.fetch("order")).map(&:to_s)
        operations = @policy.fetch("operations")
        raise ArgumentError, "transformation order is empty" if order.empty?

        duplicates = order.tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "duplicate transformations: #{duplicates.join(", ")}" unless duplicates.empty?

        missing = REQUIRED - order
        raise ArgumentError, "missing transformations: #{missing.join(", ")}" unless missing.empty?

        unknown = order - REQUIRED
        raise ArgumentError, "unknown transformations: #{unknown.join(", ")}" unless unknown.empty?

        absent = order.reject { |name| operations.key?(name) }
        raise ArgumentError, "transformation operations missing: #{absent.join(", ")}" unless absent.empty?

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
        validate_research_protocol!
        validate_restructure_contract!
        true
      rescue KeyError => e
        raise ArgumentError, "transformation policy missing #{e.key.inspect}"
      end

      private

      def index_of(name)
        operations.index { |operation| operation.name == name.to_s } || raise(ArgumentError, "unknown transformation: #{name}")
      end

      def operation_mode_known?(_name)
        modes = @policy.fetch("modes")
        raise ArgumentError, "transformation modes missing" unless modes.is_a?(Hash)
        modes.each_value { |value| raise ArgumentError, "empty transformation mode" if value.to_s.empty? }
        true
      end

      def validate_playbook!
        playbook = refactoring_playbook
        required = %w[characterize_before_change one_hat delete_before_abstract same_reason_to_change preparatory_refactoring history_as_evidence make_deletion_easy domain_first]
        ids = playbook.fetch("methods").map { |entry| entry.fetch("id") }
        missing = required - ids
        raise ArgumentError, "refactoring methods missing: #{missing.join(", ")}" unless missing.empty?
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

      def validate_research_protocol!
        protocol = research_protocol
        raise ArgumentError, "research protocol is disabled" unless protocol.fetch("enabled") == true

        minimum = Integer(protocol.fetch("minimum_source_pages"))
        max_queries = Integer(protocol.fetch("max_search_queries"))
        max_sources = Integer(protocol.fetch("max_fetched_sources"))
        raise ArgumentError, "invalid independent-source threshold" unless minimum >= 2
        raise ArgumentError, "invalid research query budget" unless (1..5).cover?(max_queries)
        raise ArgumentError, "invalid fetched-source budget" unless (2..6).cover?(max_sources)

        domains = protocol.fetch("domains")
        required = %w[engineering rails openbsd studio music visual]
        missing = required - domains.keys.map(&:to_s)
        raise ArgumentError, "research domains missing: #{missing.join(", ")}" unless missing.empty?
        domains.each do |name, row|
          queries = Array(row.fetch("queries")).map(&:to_s)
          sources = Array(row.fetch("sources")).map(&:to_s)
          raise ArgumentError, "research queries missing for #{name}" if queries.empty?
          raise ArgumentError, "research sources missing for #{name}" if sources.size < minimum
          invalid = sources.reject { |url| url.match?(%r{\Ahttps://[^\s]+\z}) }
          raise ArgumentError, "invalid research URLs for #{name}: #{invalid.join(", ")}" unless invalid.empty?
        end
        true
      rescue KeyError => e
        raise ArgumentError, "research protocol missing #{e.key.inspect}"
      end

      def policy_section(name)
        stringify_keys(@policy.fetch(name))
      end

      def stringify_keys(value)
        case value
        when Hash
          value.to_h { |key, child| [key.to_s, stringify_keys(child)] }.freeze
        when Array
          value.map { |child| stringify_keys(child) }.freeze
        else
          value
        end
      end

      def validate_restructure_contract!
        required_invariants = %w[public_api public_import_paths dependency_direction out_of_scope behavior file_creation deletion]
        missing = required_invariants - invariants.keys
        raise ArgumentError, "restructure invariants missing: #{missing.join(", ")}" unless missing.empty?

        map = candidate_map_policy
        raise ArgumentError, "invalid candidate map minimum" unless Integer(map.fetch("minimum_alternatives")).positive?
        raise ArgumentError, "invalid distinct target minimum" unless Integer(map.fetch("minimum_distinct_target_paths")).positive?
        range = Array(map.fetch("score_range")).map { |value| Integer(value) }
        raise ArgumentError, "invalid payoff/risk score range" unless range.size == 2 && range.first >= 1 && range.last <= 5 && range.first <= range.last
        missing = %w[convergence plateau veto bounded_run] - loop_policy.keys
        raise ArgumentError, "restructure terminal states missing: #{missing.join(", ")}" unless missing.empty?

        missing = REQUIRED - operation_rules.keys
        raise ArgumentError, "operation trigger/veto missing: #{missing.join(", ")}" unless missing.empty?
        operation_rules.each do |name, row|
          %w[when not_when].each do |key|
            raise ArgumentError, "#{name} operation rule missing #{key}" if row.fetch(key).to_s.empty?
          end
        end
        choices = decision_table.map { |row| row.fetch("choose") }
        raise ArgumentError, "DRY/KISS decision table incomplete" unless choices.any? { |choice| choice.include?("KISS") } && choices.any? { |choice| choice.include?("DRY") }

        scorecard = scorecard_policy
        required_metrics = %w[cohesion coupling domain_depth decision_duplication traceability concepts loc]
        missing = required_metrics - Array(scorecard.fetch("metrics")).map(&:to_s)
        raise ArgumentError, "scorecard metrics missing: #{missing.join(", ")}" unless missing.empty?
        missing = required_metrics - scorecard.fetch("measurements").keys.map(&:to_s)
        raise ArgumentError, "scorecard measurement descriptions missing: #{missing.join(", ")}" unless missing.empty?
        raise ArgumentError, "invalid scorecard history window" unless (1..500).cover?(Integer(scorecard.fetch("history_window_commits")))
        raise ArgumentError, "scorecard tie rule missing" unless scorecard.fetch("acceptance").fetch("tie") == "keep_current_tree"

        required_evidence = %w[pass_set_before_after public_constant_diff require_path_diff source_hashes_before_after scorecard_before_after ratchet_delta residual_risk]
        missing = required_evidence - Array(proof_of_equivalence.fetch("required")).map(&:to_s)
        raise ArgumentError, "equivalence evidence missing: #{missing.join(", ")}" unless missing.empty?
        %w[UNALIASED_MOVE MIXED_COMMIT SINGLE_CHILD_DIR BATCH_DELETE].each do |id|
          row = structural_gates.fetch(id)
          %w[detector positive_fixture negative_fixture].each do |key|
            raise ArgumentError, "#{id} gate missing #{key}" if row.fetch(key).to_s.empty?
          end
        end
        raise ArgumentError, "FUZZY_MOVE applicability must be explicit" if not_applicable_operations.fetch("FUZZY_MOVE").to_s.empty?
        true
      rescue KeyError => e
        raise ArgumentError, "restructure contract missing #{e.key.inspect}"
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
