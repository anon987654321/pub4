# frozen_string_literal: true

module Master
  module Fix
    # Structural signals for a tracked tree. These are measurements, not a
    # mandate to flatten protected boundaries or optimise file count at any cost.
    class TreeSprawl
      TINY_BYTES = 200
      DEEP = 5
      WIDE = 28
      MAX_CONCEPT_DEPTH = 3
      ROOT_FILE_LIMIT = 18
      IMPORTANT_CONCEPTS = %w[core fix law runtime soul].freeze
      # Repeated framework entrypoints and standard Rails templates do not
      # represent a domain concept scattered across owners.
      GENERIC_CONCEPT_STEMS = %w[
        .rubocop Gemfile README Rakefile application application_controller base base_controller
        config create.turbo_stream create.turbo_stream.html database development edit.html engine
        environment Gemfile.lock helper home_controller index index.html manifest master new.html
        pwa_controller production rails readme routes schema seeds show.html storage test_helper version
        application_reflex _card.html _form.html _live_search_results.html
      ].freeze
      UGLY_NAME_PATTERN = /(?:\A__|_{2,}|_(?:helper|utils|old)\z)/
      SIGNALS = %i[
        single_file_dirs tiny_files deep_dirs wide_dirs name_twins
        ugly_names concept_scatter depth_tax root_clutter
      ].freeze

      def initialize(files:, directories:, sizes:, root_prefix: ".")
        @files = files
        @directories = directories
        @sizes = sizes
        @root_prefix = root_prefix.to_s
      end

      def to_h = SIGNALS.to_h { |signal| [signal, public_send(signal)] }

      def single_file_dirs
        @directories.select { |dir| dir.files == 1 && target_path(dir.path) != "." }.map(&:path)
      end

      def tiny_files = @files.select { |path| @sizes.fetch(path) <= TINY_BYTES }

      def deep_dirs = @directories.select { |dir| dir.depth > DEEP }.map(&:path)

      def wide_dirs = @directories.select { |dir| dir.files > WIDE }.map(&:path)

      # host.rb and host_helper.rb: a concept split without a reason.
      def name_twins
        @files.group_by { |path| File.dirname(path) }.values.flat_map { |paths| twins_among(paths) }
      end

      # Flag path segments, not merely file extensions: __shared/, *_helper.rb,
      # *_utils.rb and *_old.rb are all names a human should review.
      def ugly_names
        @files.select do |path|
          path.split("/").any? do |segment|
            stem = File.basename(segment, File.extname(segment))
            next false if conventional_rails_helper?(path, stem)

            UGLY_NAME_PATTERN.match?(stem)
          end
        end
      end

      # lib/<owner>/ is the meaningful top-level boundary for Ruby concepts;
      # other trees use their first directory. Generic file entrypoints are
      # excluded so repeated index.rb or application.rb files are not noise.
      def concept_scatter
        @files.group_by { |path| File.basename(path, File.extname(path)) }.filter_map do |stem, paths|
          next if stem.length < 5 || GENERIC_CONCEPT_STEMS.include?(stem)

          owners = paths.map { |path| concept_owner(path) }.uniq
          [stem, paths.sort] if owners.size >= 3
        end
      end

      # Important concepts buried beyond the third path segment are hard to
      # discover and usually indicate that ownership has drifted too deep.
      def depth_tax
        @files.select do |path|
          target_path(path).split("/").each_with_index.any? do |segment, index|
            next false unless index + 1 > MAX_CONCEPT_DEPTH

            stem = File.basename(segment, File.extname(segment))
            IMPORTANT_CONCEPTS.include?(stem)
          end
        end
      end

      # Root files are counted at the measured target's boundary, not always
      # at the checkout root (a scan of MASTER/lib has its own root).
      def root_clutter
        root_files = @files.select { |path| File.dirname(target_path(path)) == "." }
        root_files.size > ROOT_FILE_LIMIT ? root_files : []
      end

      private

      # Rails deliberately names helper files with the _helper suffix, and
      # test_helper.rb is a conventional test entrypoint. They are not
      # structural naming debt. Keep __ prefixes and repeated underscores visible.
      def conventional_rails_helper?(path, stem)
        return true if stem == "test_helper"
        path_parts = path.split("/")
        return true if (path_parts.include?("test") || path_parts.include?("spec")) && stem.end_with?("_helper")

        path_parts.each_cons(2).any? { |left, right| left == "app" && right == "helpers" } &&
          stem.end_with?("_helper")
      end

      def concept_owner(path)
        parts = target_path(path).split("/")
        lib_index = parts.index("lib")
        return parts.first(lib_index + 2).join("/") if lib_index && parts.size > lib_index + 2

        parts.first
      end

      def target_path(path)
        return path if @root_prefix.empty? || @root_prefix == "."
        return "." if path == @root_prefix

        path.delete_prefix("#{@root_prefix}/")
      end

      def twins_among(paths)
        by_stem = paths.to_h { |path| [File.basename(path, File.extname(path)), path] }
        by_stem.keys.product(by_stem.keys).filter_map do |stem, other|
          [by_stem[stem], by_stem[other]] if other.start_with?("#{stem}_")
        end
      end
    end
  end
end
