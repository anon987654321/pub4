# frozen_string_literal: true

require "prism"

# PRISM VISITOR API NOTE:
# Prism dispatches via visit_TYPE_node methods — NOT a generic visit(node).
# Examples: visit_def_node, visit_if_node, visit_while_node, visit_block_node
# Define specific methods per node type, call super(node) to recurse.
# Gotcha: a generic def visit(node) override silently does nothing — depth stays 0.
# Self-test below catches this at load time: raises if known-nested code returns 0.

module MASTER
  # PrismAnalyzer — accurate code analysis using Prism's AST.
  # Replaces regex/line-counting heuristics in Analyzers with parse-accurate results.
  # Falls back gracefully if Prism fails (syntax errors in target file).
  module PrismAnalyzer
    module_function

    # Returns [{name:, start_line:, end_line:, length:, param_count:}, ...]
    # Accurate: counts AST lines, handles nested defs, single-line methods.
    def scan_methods(source)
      result = Prism.parse(source)
      return [] if result.errors.any?

      visitor = MethodCollector.new
      result.value.accept(visitor)
      visitor.methods
    end

    # Returns integer max nesting depth.
    # Counts real block nesting (if/unless/case/while/until/for/begin/rescue).
    def nesting_depth(source)
      result = Prism.parse(source)
      return 0 if result.errors.any?

      visitor = NestingDepthVisitor.new
      result.value.accept(visitor)
      visitor.max_depth
    end

    # Returns parse errors as [{message:, line:}] — useful for syntax checking.
    def parse_errors(source)
      Prism.parse(source).errors.map { |e| { message: e.message, line: e.location.start_line } }
    end

    # Walk the AST collecting DefNode entries with accurate line counts.
    class MethodCollector < Prism::Visitor
      attr_reader :methods

      def initialize
        @methods = []
      end

      def visit_def_node(node)
        loc   = node.location
        lines = loc.end_line - loc.start_line
        param_count = count_params(node.parameters)

        @methods << {
          name: node.name.to_s,
          start_line: loc.start_line,
          end_line: loc.end_line,
          length: lines,
          param_count: param_count,
        }

        super # recurse into nested defs
      end

      private

      def count_params(params)
        return 0 if params.nil?

        [
          params.requireds,
          params.optionals,
          params.keywords,
          params.posts,
        ].sum(&:size)
      end
    end

    # Walk the AST tracking nesting depth of block constructs.
    # Prism dispatches via visit_TYPE_node methods, not a generic #visit.
    class NestingDepthVisitor < Prism::Visitor
      attr_reader :max_depth

      def initialize
        @depth     = 0
        @max_depth = 0
      end

      NESTING_VISITOR_METHODS = %i[
        visit_if_node visit_unless_node visit_case_node
        visit_while_node visit_until_node visit_for_node
        visit_begin_node visit_rescue_node visit_ensure_node
        visit_block_node visit_lambda_node visit_in_node
      ].freeze

      NESTING_VISITOR_METHODS.each do |method_name|
        define_method(method_name) do |node|
          @depth += 1
          @max_depth = [@max_depth, @depth].max
          super(node)
          @depth -= 1
        end
      end
    end
  end
end

# Self-test: verify visitor dispatch works at load time.
# A generic visit(node) override silently returns 0 — this catches that.
begin
  _depth = MASTER::PrismAnalyzer.nesting_depth("def f; if true; while x; end; end; end")
  raise "PrismAnalyzer nesting_depth self-test failed: got #{_depth}, expected >= 2" unless _depth >= 2
rescue => e
  raise "PrismAnalyzer load-time self-test failed: #{e.message}"
end
