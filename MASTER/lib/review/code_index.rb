# frozen_string_literal: true

require "prism"
require "set"
require "monitor"

module Master
  module Review
    class CodeIndex
      # Read-only query surface over the built symbol/reference graph —
      # separated from CodeIndex's own build/reindex lifecycle.
      module QueryApi
        def size
          @lock.synchronize { @symbols.size }
        end

        def symbols_in(file)
          with_built_index do
            full = File.expand_path(file, @root)
            @symbols.values.select { |s| s.file == full }
          end
        end

        def find(name)
          with_built_index { find_locked(name) }
        end

        def references_to(fqn)
          with_built_index { references_for(fqn) }
        end

        def impact(fqn)
          with_built_index do
            refs = references_for(fqn)
            files = refs.map(&:from_file).uniq.map { |f| relativize(f) }
            callers = refs.map { |r| "#{relativize(r.from_file)}:#{r.from_line}" }.uniq
            { fqn:, reference_count: refs.size, files:, callers: }
          end
        end

        def summary(limit: nil)
          with_built_index do
            classes = summary_classes
            lib_count = @symbols.values.count { |s| s.file.include?("/lib/") }
            stamp = @built_at&.strftime("%H:%M") || "never"
            [
              "# Codebase: #{lib_count} lib symbols (indexed #{stamp})",
              "## Classes & Modules (#{classes.size})",
              *classes,
            ].join("\n")
          end
        end

        def query(name)
          with_built_index do
            hits = find_locked(name)
            next { error: "not found: #{name}" } if hits.empty?
            hits.map { |s| query_entry(s) }
          end
        end

        # Returns [file, line] for the first symbol matching name, or nil.
        def lookup(name)
          with_built_index do
            hit = find_locked(name).first
            hit ? [relativize(hit.file), hit.line] : nil
          end
        end
      end
    end
  end
end

module Master
  module Review
    class CodeIndex
      class SymbolVisitor < Prism::Visitor
        attr_reader :symbols, :references, :metrics

        def initialize(file:, root:)
          @file = file; @root = root
          @symbols = []; @references = []; @scope = []
          @metrics = { classes: 0, modules: 0, defs: 0 }
        end

        def visit_class_node(node)
          name = const_name(node.constant_path)
          fqn = qualified(name)
          @symbols << Symbol.new(
            fqn:,
            type: :class,
            file: @file,
            line: node.location.start_line,
            parent: node.superclass ? const_name(node.superclass) : "Object",
            includes: [],
          )
          @metrics[:classes] += 1
          @scope.push(name); super; @scope.pop
        end

        def visit_module_node(node)
          name = const_name(node.constant_path)
          fqn = qualified(name)
          @symbols << Symbol.new(
            fqn:,
            type: :module,
            file: @file,
            line: node.location.start_line,
            parent: nil,
            includes: [],
          )
          @metrics[:modules] += 1
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
            includes: [],
          )
          @metrics[:defs] += 1
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
            to_fqn:,
            ref_type: :call,
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

module Master
  module Review
  # Prism-parsed symbol graph; rebuilt on write events.
    class CodeIndex
      include QueryApi

      Symbol = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
      Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

      SUMMARY_SKIP_NAMES = %w[Entry Message Symbol CircuitError].freeze

      attr_reader :symbols, :references, :built_at

      def initialize(root:, event_bus: nil)
        @root = File.expand_path(root)
        @bus = event_bus
        @symbols = {}
        @references = []
        @mtimes = {}
        @built_at = nil
        @lock = Monitor.new
        @build_thread = nil
      end

      def build(path: nil)
        @lock.synchronize do
          target = path ? File.expand_path(path, @root) : @root
          files = Dir.glob(File.join(target, "**", "*.rb")).reject { |f| f.include?("/vendor/") }
          @built_at.nil? ? first_build(files) : incremental_build(files)
          @built_at = Time.now
          @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size)
        end
        self
      rescue StandardError => e
        @bus&.publish("code_index:error", error: e.message)
        self
      end

      def build_async
        @build_thread = Thread.new { build }
        self
      end

      def ready?
        !@built_at.nil?
      end

      def wait_for_build
        @build_thread&.join
      end

      def built?
        !@built_at.nil?
      end

      def reindex(file)
        @lock.synchronize do
          full = File.expand_path(file, @root)
          purge_file(full)
          index_file(full) if File.file?(full)
        end
      rescue StandardError => e
        @bus&.publish("code_index:reindex_error", path: file, error: e.message)
      end

      private

      def with_built_index(&blk)
        wait_for_build unless ready?
        @lock.synchronize(&blk)
      end

      def first_build(files)
        @symbols.clear
        @references.clear
        @mtimes.clear
        files.each do |f|
          index_file(f)
          @mtimes[f] = (File.mtime(f) rescue nil)
        end
      end

      def incremental_build(files)
        (@mtimes.keys - files).each { |gone| purge_file(gone) }
        changed = files.count { |f| reindex_if_stale(f) }
        @bus&.publish("code_index:incremental", changed:, total: files.size) if changed > 0
      end

      def reindex_if_stale(file)
        mt = (File.mtime(file) rescue nil)
        return false if @mtimes[file] == mt
        @mtimes[file] = mt
        true
      end

      def purge_file(full)
        @symbols.delete_if { |_, s| s.file == full }
        @references.reject! { |r| r.from_file == full }
        @mtimes.delete(full)
      end

      def references_for(fqn)
        tail = "##{fqn}"
        @references.select { |r| to = r.to_fqn; to == fqn || to.end_with?(tail) }
      end

      def relativize(file)
        file.sub("#{@root}/", "")
      end

      def find_locked(name)
        exact = @symbols[name]
        return [exact] if exact
        suffix = name.to_s
        @symbols.values.select { |sym| fqn = sym.fqn; fqn.end_with?(suffix) || fqn.include?(suffix) }
      end

      def summary_class?(sym)
        return false unless %i[class module].include?(sym.type)
        return false if sym.file.include?("/OPENBSD/") || sym.file.match?(/fix_|patch_/)
        SUMMARY_SKIP_NAMES.none? { |n| sym.fqn.end_with?("::#{n}") }
      end

      def summary_classes
        @symbols.values
                .select { |sym| summary_class?(sym) }
                .sort_by(&:fqn)
                .map { |sym| format_summary_entry(sym) }
      end

      def format_summary_entry(sym)
        parent_name = sym.parent
        parent = parent_name && parent_name != "Object" ? " < #{parent_name}" : ""
        "  #{sym.fqn}#{parent} (#{relativize(sym.file)}:#{sym.line})"
      end

      def query_entry(sym)
        refs = references_for(sym.fqn)
        {
          fqn: sym.fqn,
          type: sym.type,
          file: relativize(sym.file),
          line: sym.line,
          parent: sym.parent,
          used_in: refs.first(10).map { |r| "#{relativize(r.from_file)}:#{r.from_line}" },
        }
      end

      def index_file(file)
        src = File.read(file, encoding: "UTF-8")
        parse_result = Prism.parse(src)
        return unless parse_result.success?

        visitor = SymbolVisitor.new(file:, root: @root)
        parse_result.value.accept(visitor)
        visitor.symbols.each { |s| @symbols[s.fqn] = s }
        @references.concat(visitor.references)
      rescue StandardError => e
        @bus&.publish("code_index:parse_error", path: file, error: e.message)
      end
    end
  end
end
