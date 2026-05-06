# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      class DeadCodeRule < Rule
        def initialize
          super
          @id          = "dead_code"
          @description = "Dead constants and empty rescue blocks"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          result = Prism.parse(code)
          return [] unless result.success?

          visitor = DeadCodeVisitor.new
          visitor.visit(result.value)

          findings = []
          visitor.empty_rescues.each do |line|
            findings << finding(line:, message: "empty rescue block swallows errors silently — log or re-raise")
          end
          visitor.constant_writes.each do |name, line|
            next if visitor.constant_reads.include?(name)
            findings << finding(line:, message: "#{name} is defined but never referenced — remove it")
          end
          findings
        end

        class DeadCodeVisitor < Prism::Visitor
          attr_reader :empty_rescues, :constant_writes, :constant_reads

          def initialize
            super
            @empty_rescues   = []
            @constant_writes = {}
            @constant_reads  = []
          end

          def visit_rescue_node(node)
            stmts = node.statements
            empty = stmts.nil? || (stmts.respond_to?(:body) && stmts.body.empty?)
            @empty_rescues << node.location.start_line if empty
            super
          end

          def visit_constant_write_node(node)
            @constant_writes[node.name.to_s] ||= node.location.start_line
            super
          end

          def visit_constant_read_node(node)
            @constant_reads << node.name.to_s
            super
          end

          def visit_constant_path_node(node)
            @constant_reads << node.name.to_s if node.name
            super
          end
        end
      end
    end
  end
end
