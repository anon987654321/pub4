# frozen_string_literal: true

require "prism"
require "set"
require "monitor"
require_relative "code_index/symbol_visitor"

module Master
  # Live Prism-parsed symbol graph; rebuilt on write events.
  class CodeIndex
    Symbol = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
    Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

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
        files  = Dir.glob(File.join(target, "**", "*.rb"))
                    .reject { |f| f.include?("/vendor/") }

        if @built_at.nil?
          @symbols.clear
          @references.clear
          @mtimes.clear
          files.each do |f|
            index_file(f)
            @mtimes[f] = File.mtime(f) rescue Errno::ENOENT
          end
        else
          changed = 0
          (@mtimes.keys - files).each do |gone|
            @symbols.delete_if { |_, s| s.file == gone }
            @references.reject! { |r| r.from_file == gone }
            @mtimes.delete(gone)
          end
          files.each do |f|
            mt = File.mtime(f) rescue Errno::ENOENT
            next if @mtimes[f] == mt
            reindex(f)
            @mtimes[f] = mt
            changed += 1
          end
          @bus&.publish("code_index:incremental", changed: changed, total: files.size) if changed > 0
        end

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

    def ready?     = !@built_at.nil?
    def wait_for_build = @build_thread&.join

    def reindex(file)
      @lock.synchronize do
        full = File.expand_path(file, @root)
        @symbols.delete_if { |_, s| s.file == full }
        @references.reject! { |r| r.from_file == full }
        index_file(full) if File.file?(full)
      end
    rescue StandardError => e
      @bus&.publish("code_index:reindex_error", path: file, error: e.message)
    end

    def symbols_in(file)
      wait_for_build unless ready?
      full = File.expand_path(file, @root)
      @lock.synchronize { @symbols.values.select { |s| s.file == full } }
    end

    def find(name)
      wait_for_build unless ready?
      @lock.synchronize do
        exact = @symbols[name]
        return [exact] if exact
        suffix = name.to_s
        @symbols.values.select { |s| s.fqn.end_with?(suffix) || s.fqn.include?(suffix) }
      end
    end

    def references_to(fqn)
      wait_for_build unless ready?
      @lock.synchronize { @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") } }
    end

    def impact(fqn)
      wait_for_build unless ready?
      @lock.synchronize do
        refs = @references.select { |r| r.to_fqn == fqn || r.to_fqn.end_with?("##{fqn}") }
        files = refs.map(&:from_file).uniq.map { |f| f.sub("#{@root}/", "") }
        callers = refs.map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }.uniq
        { fqn:, reference_count: refs.size, files:, callers: }
      end
    end

    def summary(limit: nil)
      wait_for_build unless ready?
      @lock.synchronize do
        classes = @symbols.values
                          .select { |s| %i[class module].include?(s.type) }
                          .reject { |s| s.file.include?("/DEPLOY/") || s.file.match?(/fix_|patch_/) }
                          .reject { |s| %w[Entry Message Symbol CircuitError].any? { |n| s.fqn.end_with?("::#{n}") } }
                          .sort_by(&:fqn)
                          .map do |s|
          parent = s.parent && s.parent != "Object" ? " < #{s.parent}" : ""
          "  #{s.fqn}#{parent} (#{s.file.sub("#{@root}/", "")}:#{s.line})"
        end

        lib_count = @symbols.values.count { |s| s.file.include?("/lib/") }
        header = "# Codebase: #{lib_count} lib symbols (indexed #{@built_at&.strftime("%H:%M") || "never"})"
        title = "## Classes & Modules (#{classes.size})"
        [header, title, *classes].join("\n")
      end
    end

    def query(name)
      wait_for_build unless ready?
      @lock.synchronize do
        hits = find(name)
        return { error: "not found: #{name}" } if hits.empty?

        hits.map do |s|
          refs = @references.select { |r| r.to_fqn == s.fqn || r.to_fqn.end_with?("##{s.fqn}") }
          {
            fqn: s.fqn,
            type: s.type,
            file: s.file.sub("#{@root}/", ""),
            line: s.line,
            parent: s.parent,
            used_in: refs.first(10).map { |r| "#{r.from_file.sub("#{@root}/", "")}:#{r.from_line}" }
          }
        end
      end
    end

    def size  = @lock.synchronize { @symbols.size }
    def built? = !@built_at.nil?

    private

    def index_file(file)
      src = File.read(file, encoding: "UTF-8")
      result = Prism.parse(src)
      return unless result.success?

      visitor = SymbolVisitor.new(file:, root: @root)
      result.value.accept(visitor)

      visitor.symbols.each { |s| @symbols[s.fqn] = s }
      @references.concat(visitor.references)
    rescue StandardError => e
      @bus&.publish("code_index:parse_error", path: file, error: e.message)
    end

  end
end
