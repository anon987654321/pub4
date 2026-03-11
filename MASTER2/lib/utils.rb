# frozen_string_literal: true

require "did_you_mean"

module MASTER
  module Utils
    module_function

    DEFAULT_TREE_EXCLUDES = %w[. .. .git vendor tmp node_modules var].freeze

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def valid_ruby?(code)
      # NOTE: CRuby-specific (RubyVM::InstructionSequence). Will raise on JRuby/TruffleRuby.
      RubyVM::InstructionSequence.compile(code)
      true
    rescue SyntaxError, NameError
      false
    end

    def levenshtein(a, b)
      DidYouMean::Levenshtein.distance(a.to_s, b.to_s)
    end

    def similarity(a, b)
      return 1.0 if a == b
      return 0.0 if a.empty? || b.empty?

      max_len = [a.length, b.length].max
      1.0 - (levenshtein(a, b).to_f / max_len)
    end

    # Format token count (k/M notation) - ONE_SOURCE
    def format_tokens(n)
      return n.to_s if n < 1000
      return "#{(n / 1000.0).round(1)}k" if n < 1_000_000

      "#{(n / 1_000_000.0).round(1)}M"
    end

    # Compact, ASCII-only hierarchy tree with optional per-directory truncation.
    def render_tree(root, max_depth: 3, exclude: DEFAULT_TREE_EXCLUDES, max_entries_per_dir: nil)
      root = File.expand_path(root)
      lines = []
      walk_tree(root, lines:, depth: 0, max_depth:, exclude:, max_entries_per_dir:)
      lines
    end

    def walk_tree(root, lines:, depth:, max_depth:, exclude:, max_entries_per_dir:)
      return if max_depth && depth >= max_depth

      entries = Dir.children(root).sort.reject { |entry| exclude.include?(entry) }
      hidden = 0
      if max_entries_per_dir && entries.size > max_entries_per_dir
        hidden = entries.size - max_entries_per_dir
        entries = entries.first(max_entries_per_dir)
      end

      entries.each_with_index do |entry, index|
        path = File.join(root, entry)
        final_index = entries.size - 1
        final_index += 1 if hidden.positive?
        last = index == final_index
        lines << "#{tree_indent(depth, last)}#{entry}#{File.directory?(path) ? '/' : ''}"

        next unless File.directory?(path)

        walk_tree(path, lines:, depth: depth + 1, max_depth:, exclude:, max_entries_per_dir:)
      rescue SystemCallError
        next
      end

      return if hidden.zero?

      lines << "#{tree_indent(depth, true)}... (#{hidden} more entries)"
    rescue SystemCallError
      nil
    end

    def tree_indent(depth, last)
      return(last ? "`-- " : "|-- ") if depth.zero?

      ("|   " * (depth - 1)) + (last ? "`-- " : "|-- ")
    end
  end
end
