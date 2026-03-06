# frozen_string_literal: true

module MASTER
  # FileCollector - single source of truth for file discovery across the codebase.
  # Replaces scattered Dir.glob calls in self_run, multi_refactor, scan, evolve, etc.
  # (ONE_SOURCE axiom: one definition of "which files to process")
  module FileCollector
    SKIP_DIRS = %w[.git vendor tmp node_modules var log coverage .bundle].freeze

    module_function

    # Collect Ruby files from a path (file or directory, recursive).
    def ruby_files(path)
      collect(path, ["*.rb"])
    end

    # Collect all supported source files.
    def all_files(path, extensions: %w[.rb .sh .zsh .html .erb .yml .yaml .js .ts .css])
      patterns = extensions.map { |ext| "*#{ext}" }
      collect(path, patterns)
    end

    private

    module_function

    def collect(path, glob_patterns)
      path = path.to_s
      return [path] if File.file?(path)
      return [] unless File.directory?(path)

      glob_patterns.flat_map do |pattern|
        Dir.glob(File.join(path, "**", pattern))
      end.uniq.reject do |f|
        SKIP_DIRS.any? { |d| f.include?("/#{d}/") }
      end.sort
    end
  end
end
