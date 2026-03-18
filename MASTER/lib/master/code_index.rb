# frozen_string_literal: true

require "prism"

module Master
  # CodeIndex — live structural model of the Ruby codebase.
  # Parses all .rb files with Prism, builds a symbol graph:
  #   - class/module definitions with inheritance and includes
  #   - method definitions with owning class and file location
  #   - cross-file constant references and method calls
  #
  # The "digital twin" of the repo — rebuilt on write events.
  class CodeIndex
    Symbol   = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
    Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

    attr_reader :symbols, :references, :built_at

    def initialize(root:, event_bus: nil)
      @root       = root
      @bus        = event_bus
      @symbols    = {}   # fqn -> Symbol
      @references = []   # [Reference]
      @built_at   = nil
    end

    # Build (or rebuild) the index by scanning all .rb files under root.
    def build(path: nil)
      target = path ? File.expand_path(path, @root) : @root
      files  = Dir.glob(File.join(target, "**", "*.rb")).reject { |f| f.include?("/vendor/") }

      @symbols    = {}
      @references = []

      files.each { |f| index_file(f) }
      @built_at = Time.now
      @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size)
      self
    rescue StandardError => e
      @bus&.publish("code_index:error", error: e.message)
      self
    end

    # Rebuild a single file (called on write events).
    def reindex(file)
      full = File.expand_path(file, @root)
      # Remove old entries for this file
      @symbols.delete_if  { |_, s| s.file == full }
      @references.reject! { |r| r.from_file == full }
      index_file(full) if File.exist?(full)
    rescue StandardError
      nil
    end

    # All symbols defined in a given file (relative or absolute path).
    def symbols_in(file)
      full = File.expand_path(file, @root)
      @symbols.values.select { |s| s.file == full }
    end

    # Find a symbol by name (exact or suffix match). Returns array.
    def find(name)
      exact = @symbols[name]
      return [exact] if exact

      suffix = name.to_s
      @symbols.values.select { |s| s.fqn.end_with?(suffix) || s.fqn.include?(suffix) }
    end

    # All references TO a symbol (cross-file call sites / usages).
    def references_to(fqn)
      @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") || r.to_fqn == fqn }
    end

    # Impact analysis: what symbols reference this one?
    def impact(fqn)
      refs  = references_to(fqn)
      files = refs.map(&:from_file).uniq.map { |f| f.sub("#{@root}/", "") }
      callers = refs.map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }.uniq
      { fqn:, reference_count: refs.size, files:, callers: }
    end

    # Compact summary for agent context injection.
    def summary(limit: 60)
      classes = @symbols.values.select { |s| s.type == :class }.first(20)
        .map { |s| "  #{s.fqn}#{s.parent && s.parent != "Object" ? " < #{s.parent}" : ""} (#{s.file.sub("#{@root}/", "")}:#{s.line})" }

      methods = @symbols.values.select { |s| s.type == :method }.first(limit)
        .map { |s| "  #{s.fqn} (#{s.file.sub("#{@root}/", "")}:#{s.line})" }

      lines = ["# Codebase: #{@symbols.size} symbols across #{symbol_files.size} files (built #{@built_at&.strftime("%H:%M:%S") || "never"})"]
      lines << "## Classes/Modules" unless classes.empty?
      lines += classes
      lines << "## Methods (sample)" unless methods.empty?
      lines += methods
      lines.join("\n")
    end

    # For agent tool calls: return structured JSON-friendly hash.
    def query(name)
      hits = find(name)
      return { error: "not found: #{name}" } if hits.empty?

      hits.map do |s|
        refs = references_to(s.fqn)
        {
          fqn:    s.fqn,
          type:   s.type,
          file:   s.file.sub("#{@root}/", ""),
          line:   s.line,
          parent: s.parent,
          used_in: refs.first(10).map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }
        }
      end
    end

    def size     = @symbols.size
    def built?   = !@built_at.nil?

    private

    def symbol_files
      @symbols.values.map(&:file).uniq
    end

    def index_file(file)
      src    = File.read(file, encoding: "UTF-8")
      result = Prism.parse(src)
      return unless result.success?

      visitor = SymbolVisitor.new(file:, root: @root)
      result.value.accept(visitor)

      visitor.symbols.each    { |s| @symbols[s.fqn] = s }
      @references.concat(visitor.references)
    rescue StandardError
      nil  # skip unparseable files silently
    end

    # Prism visitor that walks the AST and extracts symbols + references.
    class SymbolVisitor < Prism::Visitor
      attr_reader :symbols, :references

      def initialize(file:, root:)
        @file       = file
        @root       = root
        @symbols    = []
        @references = []
        @scope      = []   # stack of current class/module names
      end

      # Class definition: class Foo < Bar
      def visit_class_node(node)
        name   = const_name(node.constant_path)
        parent = node.superclass ? const_name(node.superclass) : "Object"
        fqn    = qualified(name)

        @symbols << Symbol.new(
          fqn: fqn, type: :class, file: @file,
          line: node.location.start_line, parent: parent, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      # Module definition: module Foo
      def visit_module_node(node)
        name = const_name(node.constant_path)
        fqn  = qualified(name)

        @symbols << Symbol.new(
          fqn: fqn, type: :module, file: @file,
          line: node.location.start_line, parent: nil, includes: []
        )
        @scope.push(name)
        super
        @scope.pop
      end

      # Method definition: def foo
      def visit_def_node(node)
        method_name = node.name.to_s
        owner       = @scope.last || "(top)"
        fqn         = "#{qualified(owner)}##{method_name}"

        @symbols << Symbol.new(
          fqn: fqn, type: :method, file: @file,
          line: node.location.start_line, parent: owner, includes: []
        )
        super
      end

      # Method call: foo.bar(...) or bar(...)
      def visit_call_node(node)
        method_name = node.name.to_s
        # Skip operators and common noise
        unless method_name.match?(/\A[_a-z][a-z0-9_]*[!?]?\z/i) && method_name.length > 1
          return super
        end

        receiver_fqn = node.receiver ? const_name_safe(node.receiver) : nil
        to_fqn       = receiver_fqn ? "#{receiver_fqn}##{method_name}" : method_name

        @references << Reference.new(
          from_file: @file,
          from_line: node.location.start_line,
          to_fqn:    to_fqn,
          ref_type:  :call
        )
        super
      end

      # include / extend at class level
      def visit_call_node_include(node)
        return super unless %w[include extend prepend].include?(node.name.to_s)
        node.arguments&.arguments&.each do |arg|
          mod_name = const_name_safe(arg)
          next unless mod_name

          owner = @scope.last ? qualified(@scope.last) : "(top)"
          @references << Reference.new(
            from_file: @file,
            from_line: node.location.start_line,
            to_fqn:    mod_name,
            ref_type:  :include
          )
        end
        super
      end

      private

      def qualified(name)
        return name if @scope.empty? || name.include?("::")
        "#{@scope.join("::")}::#{name}"
      end

      def const_name(node)
        return "" unless node
        case node
        when Prism::ConstantReadNode         then node.name.to_s
        when Prism::ConstantPathNode         then "#{const_name(node.parent)}::#{node.name}"
        when Prism::ConstantPathTargetNode   then "#{const_name(node.parent)}::#{node.name}"
        else node.respond_to?(:name) ? node.name.to_s : ""
        end
      end

      def const_name_safe(node)
        return nil unless node
        name = const_name(node)
        name.empty? ? nil : name
      rescue StandardError
        nil
      end
    end
  end
end
