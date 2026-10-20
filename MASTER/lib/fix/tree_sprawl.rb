# frozen_string_literal: true

module Master
  module Fix

    # What is wrong with the shape of a file tree, as lists of paths: a folder for one file, a file
    # too small to be a concept, nesting deeper than a reader holds, a folder too wide to scan, and
    # two files in one folder where one name extends the other.
    class TreeSprawl
      TINY_BYTES = 200
      DEEP = 6
      WIDE = 40
      SIGNALS = %i[single_file_dirs tiny_files deep_dirs wide_dirs name_twins].freeze

      def initialize(files:, directories:, sizes:)
        @files = files
        @directories = directories
        @sizes = sizes
      end

      def to_h = SIGNALS.to_h { |signal| [signal, public_send(signal)] }

      def single_file_dirs = @directories.select { |dir| dir.files == 1 && dir.path != "." }.map(&:path)

      def tiny_files = @files.select { |path| @sizes.fetch(path) <= TINY_BYTES }

      def deep_dirs = @directories.select { |dir| dir.depth > DEEP }.map(&:path)

      def wide_dirs = @directories.select { |dir| dir.files > WIDE }.map(&:path)

      # host.rb and host_helper.rb: a concept split without a reason.
      def name_twins
        @files.group_by { |path| File.dirname(path) }.values.flat_map { |paths| twins_among(paths) }
      end

      private

      def twins_among(paths)
        by_stem = paths.to_h { |path| [File.basename(path, ".*"), path] }
        by_stem.keys.product(by_stem.keys).filter_map do |stem, other|
          [by_stem[stem], by_stem[other]] if other.start_with?("#{stem}_")
        end
      end
    end
  end
end
