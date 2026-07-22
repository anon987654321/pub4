# frozen_string_literal: true

require "prism"
require "set"
require "monitor"
require_relative "code_index/symbol_visitor"
require_relative "code_index/query_api"

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
