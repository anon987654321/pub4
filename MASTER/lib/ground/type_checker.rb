# frozen_string_literal: true

require "prism"

module Master
  module Ground
  # Architecture #11: constitution as a type system on the AST IR.
  # Each rule is encoded as a type constraint. Violations are type errors.
  # Fixes are derivable from the complement constraint.
  # Sound and complete — no LLM, no probabilistic inference.
  #
  # Status: scaffolded — requires a full typed IR per supported medium.
  # The Ruby path uses Prism AST nodes as the IR. Other languages TBD.
    class TypeChecker
      TypeError = Struct.new(:node, :rule, :message, :complement, keyword_init: true)

      # Run all registered constraints against the AST for +path+.
      # Returns an array of TypeErrors.
      def self.check(path, source)
        new.check(path, source)
      end

      def initialize
        @constraints = BUILT_IN_CONSTRAINTS.dup
      end

      def register(rule_id, &constraint)
        @constraints[rule_id] = constraint
        self
      end

      def check(path, source)
        return [] unless File.extname(path).downcase == ".rb"
        result = Prism.parse(source)
        return [] unless result.success?
        errors = []
        walk(node: result.value, source:, errors:)
        errors
      end

      private

      def walk(node:, source:, errors:)
        return unless node.is_a?(Prism::Node)
        @constraints.each do |rule_id, constraint|
          violation = constraint.call(node, source)
          errors << TypeError.new(node: node, rule: rule_id, **violation) if violation
        end
        node.child_nodes.compact.each { |child| walk(node: child, source:, errors:) }
      end

      # Built-in structural type constraints that don't require LLM inference.
      BUILT_IN_CONSTRAINTS = {
        FROZEN_STRING_LITERAL: lambda { |node, src|
          next unless node.is_a?(Prism::ProgramNode)
          next if src.start_with?("# frozen_string_literal: true")
          { message: "missing frozen_string_literal magic comment",
            complement: "# frozen_string_literal: true" }
        },
        BARE_RESCUE: lambda { |node, _src|
          next unless node.is_a?(Prism::RescueNode)
          next unless node.exceptions.nil? || node.exceptions.empty?
          { message: "bare rescue captures all exceptions; use rescue StandardError",
            complement: "rescue StandardError" }
        },
      }.freeze
    end
  end
end
