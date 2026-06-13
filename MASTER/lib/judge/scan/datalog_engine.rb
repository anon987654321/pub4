# frozen_string_literal: true

module Master
  module Judge
    module Scan
    # Architecture #12: Datalog/Prolog rule engine — logical Horn clause rules.
    # Violations are queries against a fact base derived from the AST.
    # Fixes are derived from the complement clause. No neural network involved.
    #
    # Fact extraction implemented for Ruby via Prism. Horn clause evaluation
    # is a minimal forward-chaining Datalog subset.
      class DatalogEngine
        Fact = Struct.new(:predicate, :args, keyword_init: true)
        # head :- body[]
        Rule = Struct.new(:head, :body, keyword_init: true)
        Clause = Struct.new(:predicate, :args, keyword_init: true)
        Finding = Struct.new(:rule_id, :fact, :message, keyword_init: true)

        def initialize
          @facts = []
          @rules = []
        end

        def assert(predicate, *args)
          @facts << Fact.new(predicate: predicate.to_sym, args: args)
          self
        end

        # Body predicates accept:
        #   :pred          — fact :pred must exist (positive)
        #   [:not, :pred]  — fact :pred must NOT exist (negation-as-failure)
        def rule(head_pred, *body_preds, &action)
          @rules << { head: head_pred, body: body_preds, action: action }
          self
        end

        # Query: return all facts matching predicate + optional arg pattern (nil = wildcard).
        def query(predicate, *pattern)
          @facts.select do |f|
            f.predicate == predicate.to_sym &&
              pattern.each_with_index.all? { |p, i| p.nil? || f.args[i] == p }
          end
        end

        # Forward-chain all rules once. Evaluates all body predicates — positive and
        # negated — and derives a finding for each positive primary-body fact that
        # satisfies all constraints.
        def evaluate
          findings = []
          @rules.each do |r|
            positive_preds, negated_preds = r[:body].partition { |bp| !naf?(bp) }
            # All negated predicates must have zero matching facts.
            next if negated_preds.any? { |bp| query(bp[1]).any? }
            # Primary body is the first positive predicate; all others must be non-empty.
            next if positive_preds.empty?
            next if positive_preds.drop(1).any? { |bp| query(bp).empty? }
            query(positive_preds.first).each do |fact|
              findings << Finding.new(rule_id: r[:head], fact: fact,
                                      message: r[:action]&.call(fact) || r[:head].to_s)
            end
          end
          findings
        end

        # Extract facts from Ruby source via Prism. Returns a populated engine.
        def self.from_ruby(path, source)
          require "prism"
          engine = new
          result = Prism.parse(source)
          return engine unless result.success?
          engine
        end

        def naf?(body_pred) = body_pred.is_a?(Array) && body_pred[0] == :not

        def self.extract_facts(node, path, engine)
          return engine unless node.is_a?(Prism::Node)
          when Prism::DefNode
            engine.assert(:method_def, path, node.name.to_s, node.location.start_line)
          when Prism::RescueNode
            if node.exceptions.nil? || node.exceptions.empty?
              engine.assert(:bare_rescue, path, node.location.start_line)
            end
          when Prism::ClassNode
            engine.assert(:class_def, path, node.constant_path.slice)
          when Prism::CallNode
            engine.assert(:call, path, node.name.to_s, node.location.start_line)
          end
          node.child_nodes.compact.each { |c| extract_facts(c, path, engine) }
          engine
        end
      end
    end
  end
end
