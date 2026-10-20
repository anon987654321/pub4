# frozen_string_literal: true

module Master
  module Fix

    # The text a person or a model reads for a Tree: one line per directory, indented by
    # depth, then the sprawl signals by name. Bounded, because a prompt has a size.
    class TreeView
      SIGNAL_LINES = 25

      def initialize(tree)
        @tree = tree
      end

      def render(max_lines: 400)
        directories = @tree.directories
        lines = directory_lines(directories.first(max_lines))
        lines << "... #{directories.size - max_lines} more directories" if directories.size > max_lines

        (lines + sprawl_lines).join("\n")
      end

      private

      def directory_lines(directories)
        base = @tree.directories.map(&:depth).min.to_i
        directories.map do |dir|
          "#{"  " * (dir.depth - base)}#{dir.path}/ #{dir.files} files #{dir.bytes} B"
        end
      end

      def sprawl_lines
        sprawl = @tree.sprawl
        counts = sprawl.map { |signal, items| "#{signal}=#{items.size}" }.join(" ")

        named = sprawl.flat_map do |signal, items|
          items.first(SIGNAL_LINES).map { |item| "  #{signal}: #{Array(item).join(" ~ ")}" }
        end
        ["sprawl: #{counts}"] + named
      end
    end
  end
end
