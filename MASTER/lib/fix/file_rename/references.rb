# frozen_string_literal: true

require_relative "../../operator/readers"

module Master
  module Fix
    class FileRename
      # Every spelling that names a renamed file, across the three governed trees, and the
      # rewrite from old to new. Only exact forms: the basename, the `_stem` a
      # comment or partial uses, and the bare name in a Sass @use/@forward/@import.
      # A plain word match would rewrite "base" in every sentence that says it.
      module References
        SASS_LOAD = /(@(?:use|forward|import)\s+["'](?:[^"']*\/)?)%<name>s(["'])/

        def self.forms(from, to)
          old_base = File.basename(from)
          new_base = File.basename(to)
          old_stem = old_base.sub(/\..*\z/, "")
          new_stem = new_base.sub(/\..*\z/, "")
          pairs = [[old_base, new_base], [old_stem, new_stem]]
          pairs << [old_stem.delete_prefix("_"), new_stem.delete_prefix("_")] if old_stem.start_with?("_")
          pairs.uniq
        end

        # The rewritten text, or nil when the file names nothing it knows.
        def self.rewrite(text, from, to)
          out = text.dup
          forms(from, to).each do |old, new|
            if old.start_with?("_") || old.include?(".")
              out.gsub!(/(?<![\w-])#{Regexp.escape(old)}(?![\w-])/, new)
            else
              out.gsub!(Regexp.new(format(SASS_LOAD.source, name: Regexp.escape(old)))) { "#{$1}#{new}#{$2}" }
            end
          end
          out == text ? nil : out
        end

        # Files that still spell the old name: a rewrite would change them.
        def self.remaining(root, from, to)
          each_file(root).select do |path|
            text = File.read(path, encoding: "UTF-8")
            text.valid_encoding? && !rewrite(text, from, to).nil?
          rescue ArgumentError
            false
          end
        end

        def self.each_file(root)
          Operator::Readers::TREES.flat_map do |tree|
            Dir.glob(File.join(root, tree, "**", "*")).reject do |path|
              path.match?(Operator::Readers::SKIP) || path.include?("/builds/") || !File.file?(path) ||
                File.size(path) > 2_000_000
            end
          end
        end
      end
    end
  end
end
