# frozen_string_literal: true

# Architect — Automated fresh-eyes architectural health assessment.
# Produces the same "step back and look at the whole codebase" analysis
# that was previously done manually, now runnable anytime via `> architect`.
#
# Checks:
#   1. File counts and LOC per top-level lib/ namespace
#   2. Namespace duplication (two dirs doing similar things)
#   3. Thin files (< 20 LOC of actual code — likely should be merged)
#   4. Data file inventory: orphaned, tiny, or comment-only
#   5. Accretion index: ratio of lib files to data concepts (signal for over-engineering)
#   6. Critical path estimation: which files are on the hot path (most required-by others)

module MASTER
  module Friction
    module Architect
      THIN_FILE_THRESHOLD = 20   # lines of non-blank, non-comment code
      ACCRETION_WARNING   = 10.0 # lib_files / data_concepts ratio above this is suspicious

      def self.run
        root      = MASTER.root
        lib_root  = File.join(root, "lib")
        data_root = File.join(root, "data")

        {
          lib:          analyze_lib(lib_root),
          data:         analyze_data(data_root),
          duplication:  find_namespace_duplication(lib_root),
          thin_files:   find_thin_files(lib_root),
          critical_path: estimate_critical_path(lib_root),
          accretion:    accretion_index(lib_root, data_root),
        }
      end

      def self.format_report(report)
        lines = ["", "─" * 60, "  ARCHITECT: Fresh-Eyes Assessment", "─" * 60, ""]

        # 1. Lib overview
        lib = report[:lib]
        lines << "LIB  #{lib[:total_files]} files  #{lib[:total_loc]} LOC  " \
                 "#{lib[:namespaces].size} top-level namespaces"
        lines << ""
        lines << "  Top namespaces by file count:"
        lib[:namespaces].sort_by { |_, v| -v[:files] }.first(10).each do |ns, data|
          lines << "    %-22s  %3d files  %5d LOC" % [ns, data[:files], data[:loc]]
        end
        lines << ""

        # 2. Data overview
        data = report[:data]
        lines << "DATA  #{data[:total_files]} files  #{data[:total_loc]} LOC"
        dead = data[:dead_files]
        if dead.any?
          lines << "  Dead/comment-only data files (safe to delete):"
          dead.each { |f| lines << "    #{File.basename(f)}" }
        end
        lines << ""

        # 3. Namespace duplication
        dups = report[:duplication]
        if dups.any?
          lines << "DUPLICATION  #{dups.size} suspicious namespace pair(s):"
          dups.each { |d| lines << "    #{d}" }
        else
          lines << "DUPLICATION  none detected"
        end
        lines << ""

        # 4. Thin files
        thin = report[:thin_files]
        if thin.any?
          lines << "THIN FILES  #{thin.size} file(s) with < #{THIN_FILE_THRESHOLD} code lines:"
          thin.first(10).each { |f| lines << "    #{f[:path].sub(MASTER.root + '/', '')}  (#{f[:loc]} LOC)" }
          lines << "    ... #{thin.size - 10} more" if thin.size > 10
        else
          lines << "THIN FILES  none"
        end
        lines << ""

        # 5. Accretion index
        acc = report[:accretion]
        flag = acc[:index] > ACCRETION_WARNING ? "  ⚠ HIGH" : ""
        lines << "ACCRETION  #{acc[:lib_files]} lib files / #{acc[:data_concepts]} data concepts" \
                 " = #{format('%.1f', acc[:index])}x#{flag}"
        lines << ""

        # 6. Critical path
        lines << "CRITICAL PATH  (most required-by: likely core files)"
        report[:critical_path].first(8).each do |f|
          lines << "    %-40s  required by %d" % [f[:name], f[:required_by]]
        end
        lines << ""
        lines << "─" * 60
        lines.join("\n")
      end

      class << self
        private

        def analyze_lib(lib_root)
          all_rb = Dir.glob("#{lib_root}/**/*.rb")
          namespaces = {}

          all_rb.each do |f|
            rel      = f.sub("#{lib_root}/", "")
            ns       = rel.split("/").first.sub(/\.rb$/, "")
            loc      = code_lines(f)
            namespaces[ns] ||= { files: 0, loc: 0 }
            namespaces[ns][:files] += 1
            namespaces[ns][:loc]   += loc
          end

          { total_files: all_rb.size, total_loc: namespaces.values.sum { |v| v[:loc] }, namespaces: namespaces }
        end

        def analyze_data(data_root)
          all_yml = Dir.glob("#{data_root}/*.{yml,yaml,json}")
          dead    = all_yml.select { |f| dead_data_file?(f) }
          total_loc = all_yml.sum { |f| File.readlines(f).count }
          { total_files: all_yml.size, total_loc: total_loc, dead_files: dead }
        end

        # A data file is "dead" if it has ≤ 3 lines and they're all comments or blank
        def dead_data_file?(path)
          lines = File.readlines(path).map(&:strip).reject(&:empty?)
          lines.size <= 3 && lines.all? { |l| l.start_with?("#") }
        end

        def find_namespace_duplication(lib_root)
          dirs = Dir.glob("#{lib_root}/*/").map { |d| File.basename(d) }
          suspicious = []

          # Known overlap patterns to flag
          overlap_groups = [
            %w[review code_review enforcement],
            %w[introspection analysis],
            %w[chamber agent],
            %w[session workflow],
            %w[logging logging],
          ]

          overlap_groups.each do |group|
            present = group.uniq & dirs
            suspicious << present.join(" ↔ ") if present.size >= 2
          end

          suspicious.uniq
        end

        def find_thin_files(lib_root)
          Dir.glob("#{lib_root}/**/*.rb").filter_map do |f|
            loc = code_lines(f)
            { path: f, loc: loc } if loc < THIN_FILE_THRESHOLD && loc > 0
          end.sort_by { |f| f[:loc] }
        end

        def estimate_critical_path(lib_root)
          # Count how many other files require each file
          all_rb  = Dir.glob("#{lib_root}/**/*.rb")
          counts  = Hash.new(0)

          all_rb.each do |file|
            File.readlines(file).each do |line|
              next unless line =~ /require_relative\s+['"](.*)['"]/
              target = Regexp.last_match(1)
              counts[target] += 1
            end
          end

          counts.map { |name, n| { name: name, required_by: n } }
                .sort_by { |f| -f[:required_by] }
        end

        def accretion_index(lib_root, data_root)
          lib_files     = Dir.glob("#{lib_root}/**/*.rb").size
          data_concepts = Dir.glob("#{data_root}/*.{yml,yaml,json}").size
          index = data_concepts.positive? ? lib_files.to_f / data_concepts : lib_files.to_f
          { lib_files: lib_files, data_concepts: data_concepts, index: index }
        end

        def code_lines(path)
          File.readlines(path).count do |l|
            stripped = l.strip
            stripped.length > 0 && !stripped.start_with?("#")
          end
        rescue Errno::ENOENT
          0
        end
      end
    end
  end
end
