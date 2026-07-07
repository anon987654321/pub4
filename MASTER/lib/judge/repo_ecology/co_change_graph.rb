# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

module Master
  module Judge
    class RepoEcology
      module CoChangeGraph
        private

        def build_co_change_graph
          out, status = Master::Reach::Exec.capture2e("git", "-C", @root, "log", "--name-only",
                                        "--pretty=format:#{COMMIT_SEPARATOR}",
                                        "-#{CO_CHANGE_COMMITS}")
          return {} unless status.success?
          pair_counts = Hash.new(0)
          out.split(COMMIT_SEPARATOR).each do |chunk|
            files = chunk.lines.map(&:strip).reject(&:empty?).uniq
            next if files.size < 2
            files.combination(2) { |a, b| pair_counts[[a, b].sort] += 1 }
          end
          graph = Hash.new { |h, k| h[k] = {} }
          pair_counts.each do |(a, b), count|
            next if count < CO_CHANGE_MIN_COUNT
            graph[a][b] = count
            graph[b][a] = count
          end
          graph.transform_values(&:freeze).freeze
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_error", error: e.message)
          {}
        end

        def load_or_build_co_change_graph
          cached = read_co_change_cache
          return cached if cached

          build_co_change_graph.tap { |graph| write_co_change_cache(graph) }
        end

        def read_co_change_cache
          path = co_change_cache_path
          return unless File.exist?(path)

          data = YAML.safe_load_file(path, aliases: true)
          return unless data.is_a?(Hash) && data["head_mtime"].to_i == git_head_mtime

          thaw_graph(data["graph"] || {})
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_cache_error", error: e.message)
          nil
        end

        def write_co_change_cache(graph)
          path = co_change_cache_path
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, { "head_mtime" => git_head_mtime, "graph" => graph }.to_yaml)
        rescue StandardError => e
          @bus&.publish("repo_ecology:co_change_cache_error", error: e.message)
        end

        def thaw_graph(graph)
          graph.each_with_object({}) do |(file, peers), acc|
            acc[file] = (peers || {}).transform_values(&:to_i).freeze
          end.freeze
        end

        def co_change_cache_path
          File.join(@root, CO_CHANGE_CACHE_PATH)
        end

        def git_head_mtime
          File.mtime(File.join(@root, ".git", "HEAD")).to_i
        rescue StandardError
          0
        end
      end
    end
  end
end
