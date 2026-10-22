# frozen_string_literal: true

require "set"
require_relative "../boot/paths"
require_relative "../io/exec"
require_relative "tree_sprawl"

module Master
  module Fix

    # The first thing /fix does: lay out the tracked files of the target as a tree and
    # measure where it sprawls, before any Law reads a line. The tree is deterministic,
    # so two runs over the same commit print the same text (TreeView) and TreeReasoning's
    # proposals can be checked against it path by path.
    class Tree
      Entry = Struct.new(:path, :files, :bytes, :depth, keyword_init: true)

      def initialize(root:, target: nil)
        @root = File.expand_path(root)
        @target = normalize_target(target)
      end

      # Repository-relative paths of tracked files under the target, sorted.
      def files
        @files ||= tracked.select { |path| File.file?(File.join(@root, path)) }.sort
      end

      # Every directory holding tracked files, with its own file count and size.
      def directories
        @directories ||= files.group_by { |path| File.dirname(path) }.sort.map do |dir, paths|
          Entry.new(path: dir, files: paths.size, bytes: paths.sum { |path| size(path) },
                    depth: dir == "." ? 0 : dir.count("/") + 1)
        end
      end

      # Every path the tree names: files and each directory above them. TreeReasoning
      # refuses a proposal that names anything else.
      def paths
        @paths ||= files.flat_map { |path| ancestors(path) + [path] }.to_set
      end

      def sprawl
        @sprawl ||= TreeSprawl.new(files:, directories:, sizes: files.to_h { |path| [path, size(path)] }).to_h
      end

      def metrics
        { target: relative(@target), files: files.size, directories: directories.size,
          bytes: directories.sum(&:bytes), sprawl: sprawl.transform_values(&:size) }
      end

      private

      def normalize_target(target)
        text = target.to_s.strip
        return @root if text.empty?

        if text.start_with?("../")
          candidate = text.delete_prefix("../")
          text = candidate if MasterPaths::TREES.any? { |tree| candidate == tree || candidate.start_with?("#{tree}/") }
        end
        full = File.expand_path(text, @root)
        return full if full == @root || full.start_with?("#{@root}#{File::SEPARATOR}")

        raise ArgumentError, "tree target outside repository root: #{target.inspect}"
      end

      def tracked
        out, status = Master::Io::Exec.capture2e("git", "-C", @root, "ls-files", "-z", "--", relative(@target))
        raise "tree inventory failed: #{out.to_s.strip}" unless status.success?

        out.split("\0").reject(&:empty?)
      end

      def size(path) = File.size(File.join(@root, path))

      def ancestors(path)
        parts = File.dirname(path).split("/")
        parts.each_index.map { |index| parts[0..index].join("/") }.reject { |dir| dir == "." }
      end

      def relative(path)
        full = File.expand_path(path.to_s)
        full == @root ? "." : full.delete_prefix("#{@root}/")
      end
    end
  end
end
