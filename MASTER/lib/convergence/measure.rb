# frozen_string_literal: true

require "time"
require "open3"

module Master
  module Convergence
    module Measure
      ROOTS = Master::Convergence::ROOTS

      module_function

      def inventory(root: Master::REPO_ROOT)
        trees = ROOTS.to_h { |tree| [tree, tree_inventory(root, tree)] }
        {
          generated_at: Time.now.utc.iso8601,
          git: git_head(root),
          totals: {
            files: trees.values.sum { |row| row[:files] },
            bytes: trees.values.sum { |row| row[:bytes] },
          },
          trees: trees,
        }
      end

      def render(root: Master::REPO_ROOT)
        data = inventory(root:)
        lines = [
          "converge0: git=#{data[:git]}",
          "converge0: files=#{data[:totals][:files]} bytes=#{data[:totals][:bytes]}",
        ]
        data[:trees].each do |name, row|
          lines << "converge0: #{name} files=#{row[:files]} bytes=#{row[:bytes]} ruby_lines=#{row[:ruby_lines]}"
        end
        largest = data[:trees].flat_map { |tree, row|
          row[:largest].map { |entry| [tree, entry] }
        }.sort_by { |_tree, entry| -entry[:bytes] }.first(10)
        largest.each do |tree, entry|
          lines << "converge0: largest #{tree}/#{entry[:path]} bytes=#{entry[:bytes]}"
        end
        lines.join("\n")
      end

      def tree_inventory(root, tree)
        base = File.join(root, tree)
        return { files: 0, bytes: 0, ruby_lines: 0, largest: [] } unless File.directory?(base)

        files = Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
        entries = files.map do |path|
          [path.delete_prefix("#{root}/"), File.size(path)]
        end
        {
          files: entries.size,
          bytes: entries.sum { |_path, bytes| bytes },
          ruby_lines: files.select { |path| ruby?(path) }.sum { |path| File.foreach(path).count },
          largest: entries.sort_by { |_path, bytes| -bytes }.first(12).map { |path, bytes| { path:, bytes: } },
        }
      end

      def ruby?(path)
        File.extname(path) == ".rb" || %w[Gemfile Rakefile Guardfile].include?(File.basename(path))
      end

      def git_head(root)
        out, status = Open3.capture2("git", "-C", root, "rev-parse", "--short", "HEAD")
        status.success? ? out.strip : "unavailable"
      rescue StandardError
        "unavailable"
      end
    end
  end
end
