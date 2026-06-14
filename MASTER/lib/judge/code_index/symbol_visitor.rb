# frozen_string_literal: true

require "prism"

module Master
  module Judge
    class CodeIndex
      class SymbolVisitor < Prism::Visitor
        attr_reader :symbols, :references

        def initialize(file:, root:)
          @file = file; @root = root
          @symbols = []; @references = []; @scope = []
        end

        def visit_class_node(node)
          name = const_name(node.constant_path)
          fqn = qualified(name)
          @symbols << Symbol.new(
            fqn: fqn,
            type: :class,
            file: @file,
            line: node.location.start_line,
            parent: node.superclass ? const_name(node.superclass) : "Object",
            includes: []
          )
          @scope.push(name); super; @scope.pop
        end

        def visit_module_node(node)
          name = const_name(node.constant_path)
          fqn = qualified(name)
          @symbols << Symbol.new(
            fqn: fqn,
            type: :module,
            file: @file,
            line: node.location.start_line,
            parent: nil,
            includes: []
          )
          @scope.push(name); super; @scope.pop
        end

        def visit_def_node(node)
          meth = node.name.to_s
          owner = @scope.last || "(top)"
          @symbols << Symbol.new(
            fqn: "#{qualified(owner)}##{meth}",
            type: :method,
            file: @file,
            line: node.location.start_line,
            parent: owner,
            includes: []
          )
          super
        end

        def visit_call_node(node)
          method_name = node.name.to_s
          return super unless method_name.match?(/\A[_a-z][a-z0-9_]*[!?]?\z/i) && method_name.length > 1
          receiver = receiver_name(node.receiver)
          to_fqn = receiver ? "#{receiver}##{method_name}" : method_name
          @references << Reference.new(
            from_file: @file,
            from_line: node.location.start_line,
            to_fqn: to_fqn,
            ref_type: :call
          )
          super
        end

        private

        def qualified(name)
          return name if @scope.empty? || name.include?("::")
          (@scope + [name]).join("::")
        end

        def receiver_name(node)
          case node
          when Prism::SelfNode
            @scope.join("::")
          when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode
            const_name_safe(node)
          else
            nil
          end
        end

        def const_name(node)
          case node
          when Prism::ConstantReadNode then node.name.to_s
          when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
            "#{const_name(node.parent)}::#{node.name}"
          else node.respond_to?(:name) ? node.name.to_s : ""
          end
        end

        def const_name_safe(node)
          name = const_name(node)
          name.empty? ? nil : name
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "code_index.const_name_safe")
          nil
        end
      end
    end
  end
end
