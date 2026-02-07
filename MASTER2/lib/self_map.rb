# frozen_string_literal: true

module MASTER
  module SelfMap
    EXCLUDE_PATTERNS = [
      /\A\./, # dotfiles/dotfolders
      /\Atmp\z/,
      /\Alog\z/,
      /\Anode_modules\z/,
      /\Avendor\z/,
      /\.db\z/,
    ].freeze

    class << self
      def tree(root: MASTER.root, depth: 0, max_depth: 10)
        return [] if depth > max_depth
        return [] unless File.directory?(root)

        entries = Dir.entries(root).sort - [".", ".."]
        entries.reject! { |e| EXCLUDE_PATTERNS.any? { |p| e.match?(p) } }

        entries.flat_map do |entry|
          full_path = File.join(root, entry)
          relative = full_path.sub("#{MASTER.root}/", "")

          if File.directory?(full_path)
            [{ path: relative, type: :dir }] + tree(root: full_path, depth: depth + 1, max_depth: max_depth)
          else
            [{ path: relative, type: :file, size: File.size(full_path), ext: File.extname(entry) }]
          end
        end
      end

      def files(root: MASTER.root, extensions: nil)
        all = tree(root: root)
        result = all.select { |e| e[:type] == :file }
        result = result.select { |e| extensions.include?(e[:ext]) } if extensions
        result
      end

      def ruby_files(root: MASTER.root)
        files(root: root, extensions: [".rb"])
      end

      def yaml_files(root: MASTER.root)
        files(root: root, extensions: [".yml", ".yaml"])
      end

      def summary
        all = tree
        dirs = all.count { |e| e[:type] == :dir }
        file_entries = all.select { |e| e[:type] == :file }
        total_size = file_entries.sum { |e| e[:size] || 0 }
        by_ext = file_entries.group_by { |e| e[:ext] }.transform_values(&:count)

        {
          root: MASTER.root,
          directories: dirs,
          files: file_entries.length,
          total_bytes: total_size,
          by_extension: by_ext
        }
      end

      # Can MASTER target itself?
      def self_aware?
        File.exist?("#{MASTER.root}/lib/master.rb") &&
          File.exist?("#{MASTER.root}/data/axioms.yml") &&
          File.exist?("#{MASTER.root}/data/council.yml")
      end

      # Target a directory for processing — returns files grouped by type
      def target(directory)
        root = File.expand_path(directory, MASTER.root)
        return Result.err("Directory not found: #{root}") unless File.directory?(root)

        all_files = files(root: root)

        grouped = {
          ruby: all_files.select { |f| f[:ext] == ".rb" },
          yaml: all_files.select { |f| [".yml", ".yaml"].include?(f[:ext]) },
          markdown: all_files.select { |f| f[:ext] == ".md" },
          shell: all_files.select { |f| f[:ext] == ".sh" || f[:ext] == "" },
          other: all_files.reject { |f| [".rb", ".yml", ".yaml", ".md", ".sh", ""].include?(f[:ext]) }
        }

        Result.ok(grouped)
      end
    end
  end
end
