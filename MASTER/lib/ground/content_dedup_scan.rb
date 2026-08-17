# frozen_string_literal: true

module Master
  module Ground
    # Periodic duplicate-content scanner for MASTER's own config/constitution
    # files, matching OpenCrabs' dedup_scan.rs -- reads each file, flags exact
    # duplicate lines (within a file or across files), reported for human
    # review (never auto-applied: which copy is "right" when two differ even
    # slightly isn't safe to guess, unlike PrincipleMapRepair's dangling-
    # reference removal, which can't lose information either way).
    #
    # Conservative on purpose: short/structural lines repeat constantly and
    # legitimately in YAML (`status: covered`, `- ui`) -- only lines at or
    # above MIN_LINE_LEN are considered, filtering most of that noise without
    # needing per-file schema knowledge.
    module ContentDedupScan
      MIN_LINE_LEN = 30
      MIN_DUPLICATE_COUNT = 2

      DEFAULT_FILES = %w[
        data/soul.yml data/rules.yml data/principle_map.yml
        data/patterns.yml
      ].freeze

      Duplicate = Struct.new(:text, :count, :locations, keyword_init: true)

      module_function

      # Returns Duplicate structs for every line (>= MIN_LINE_LEN, non-blank)
      # that appears more than once across the given files (default:
      # DEFAULT_FILES under root). locations are "relative/path:line_no".
      def scan(root: Master::ROOT, files: DEFAULT_FILES)
        occurrences = Hash.new { |h, k| h[k] = [] }
        files.each do |rel|
          path = File.join(root, rel)
          next unless File.file?(path)

          File.foreach(path).with_index(1) do |line, num|
            text = line.strip
            next if text.length < MIN_LINE_LEN

            occurrences[text] << "#{rel}:#{num}"
          end
        end

        occurrences.filter_map do |text, locations|
          next if locations.size < MIN_DUPLICATE_COUNT

          Duplicate.new(text:, count: locations.size, locations:)
        end.sort_by { |dup| -dup.count }
      end
    end
  end
end
