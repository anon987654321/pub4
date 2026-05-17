# frozen_string_literal: true

require "prism"

module Master
  module Judge
  module Scan
  # Architecture #4: deterministic AST-level autofixes for mechanical rules.
  # No LLM call, no token cost. Applied before LLM sweep on every scan cycle.
  # Each transform is idempotent — safe to apply repeatedly.
  class AstFixer
    FROZEN_HEADER  = "# frozen_string_literal: true\n"
    BARE_RESCUE_RE = /^(\s*)rescue(\s*\n|\s*=>)/.freeze

    Result = Struct.new(:path, :changed, :transforms, keyword_init: true)

    # Apply all eligible fixes to +source+ for +path+.
    # Returns Result with :changed (bool) and :transforms (array of applied fix names).
    def self.fix(path, source)
      new(path, source).apply
    end

    def initialize(path, source)
      @path       = path
      @source     = source
      @transforms = []
    end

    def apply
      out = @source
      out = add_frozen_header(out)       if ruby?
      out = fix_bare_rescue(out)         if ruby?
      out = normalise_null_comparison(out) if sql_in_ruby?
      changed = out != @source
      Result.new(path: @path, changed: changed, transforms: @transforms)
        .tap { write_back(out) if changed }
    end

    private

    # Add frozen_string_literal comment if absent.
    def add_frozen_header(src)
      return src if src.start_with?(FROZEN_HEADER)
      # Preserve shebang if present.
      if src.start_with?("#!")
        lines = src.lines
        lines.insert(1, FROZEN_HEADER)
        @transforms << :frozen_string_literal
        lines.join
      else
        @transforms << :frozen_string_literal
        FROZEN_HEADER + "\n" + src.lstrip
      end
    end

    # Replace bare `rescue` with `rescue StandardError`.
    # Only fires when Prism confirms the rescue is genuinely bare (no class listed).
    def fix_bare_rescue(src)
      result = Prism.parse(src)
      return src unless result.success?

      bare_lines = bare_rescue_lines(result.value)
      return src if bare_lines.empty?

      lines = src.lines
      bare_lines.each do |lineno|
        idx = lineno - 1
        next unless idx < lines.size
        lines[idx] = lines[idx].sub(/\brescue\b(?!\s+\w)/, "rescue StandardError")
      end
      @transforms << :bare_rescue
      lines.join
    end

    # `= NULL` → `IS NULL`, `!= NULL` → `IS NOT NULL` inside SQL heredocs/strings.
    def normalise_null_comparison(src)
      changed = false
      out = src.gsub(/(?<![<>!])=\s*NULL\b/i) { changed = true; "IS NULL" }
               .gsub(/!=\s*NULL\b/i)           { changed = true; "IS NOT NULL" }
               .gsub(/<>\s*NULL\b/i)            { changed = true; "IS NOT NULL" }
      @transforms << :null_comparison if changed
      out
    end

    def bare_rescue_lines(node, lines = [])
      return lines unless node.is_a?(Prism::Node)
      if node.is_a?(Prism::RescueNode) && (node.exceptions.nil? || node.exceptions.empty?)
        lines << node.location.start_line
      end
      node.child_nodes.compact.each { |child| bare_rescue_lines(child, lines) }
      lines
    end

    def ruby? = File.extname(@path).downcase == ".rb"

    def sql_in_ruby?
      ruby? || %w[.sql .erb].include?(File.extname(@path).downcase)
    end

    def write_back(content)
      require_relative "../../reach/atomic_write"
      tmp = "#{@path}.ast_fix.#{Process.pid}.tmp"
      File.write(tmp, content, encoding: "UTF-8")
      File.rename(tmp, @path)
    rescue StandardError => e
      File.delete(tmp) if defined?(tmp) && File.exist?(tmp) rescue nil
      raise e
    end
  end
  end
  end
end
