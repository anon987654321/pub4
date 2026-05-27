# frozen_string_literal: true

require "prism"
require "open3"

module Master
  module Judge
  # Extracts the public API surface (methods, classes, modules, constants)
  # from Ruby source via Prism. Used by CommitGuard to detect omissions.
  module AstSignature
    Sig = Data.define(:type, :name, :line)
    module_function

    def from_source(source)
      result = Prism.parse(source)
      return [] if result.failure?
      visitor = Visitor.new
      visitor.visit(result.value)
      visitor.sigs
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "ast_signature.from_source")
      []
    end

    def from_git(rel_path, ref:, root: Dir.pwd)
      out, st = Open3.capture2e("git", "show", "#{ref}:#{rel_path}", chdir: root)
      return [] unless st.success?
      from_source(out)
    end

    def diff(old_sigs, new_sigs, kinds: %i[method class module])
      new_names = new_sigs.select { |s| kinds.include?(s.type) }.map(&:name).to_set
      old_sigs.select { |s| kinds.include?(s.type) && !new_names.include?(s.name) }
    end

    class Visitor < Prism::Visitor
      attr_reader :sigs
      def initialize = (@sigs = []; @ns = [])

      def visit_module_node(node)
        name = node.constant_path.slice
        full = fqn(name)
        @ns.push(name)
        @sigs << Sig.new(type: :module, name: full, line: node.location.start_line)
        super
        @ns.pop
      end

      def visit_class_node(node)
        name = node.constant_path.slice
        full = fqn(name)
        @ns.push(name)
        @sigs << Sig.new(type: :class, name: full, line: node.location.start_line)
        super
        @ns.pop
      end

      def visit_def_node(node)
        base = @ns.join("::")
        sep = node.receiver&.is_a?(Prism::SelfNode) ? "." : "#"
        full = base.empty? ? node.name.to_s : "#{base}#{sep}#{node.name}"
        @sigs << Sig.new(type: :method, name: full, line: node.location.start_line)
      end

      def visit_constant_write_node(node)
        @sigs << Sig.new(type: :constant, name: fqn(node.name.to_s), line: node.location.start_line)
        super
      end

      def visit_constant_path_write_node(node)
        @sigs << Sig.new(type: :constant, name: node.target.slice, line: node.location.start_line)
        super
      end

      private
      def fqn(name) = (@ns + [name]).join("::")
    end
  end
  end
end
