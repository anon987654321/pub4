# frozen_string_literal: true

require "open3"

module Master
  module Judge
  module Scan
    module Rules
      # Files that change together in many commits are coupled regardless of imports.
      # Mines the last N commits, builds adjacency, flags pairs whose weight exceeds
      # threshold and that live in different top-level module paths — likely DECOUPLE
      # candidates the lexical rules can't see.
      class CoChangeCouplingRule < Rule
        COMMITS_WINDOW = 500
        WEIGHT_THRESHOLD = 5
        # Skip mega-commits — they pollute the graph.
        MAX_FILES_IN_COMMIT = 12

        def initialize
          super
          @id = "co_change_coupling"
          @description = "Files co-change with N+ peers across module boundaries — hidden coupling"
          @severity = :info
          @rule_tags = %i[DECOUPLE ONE_JOB]
          @graph_mutex = Mutex.new
          @graph = nil
        end

        def check(_code, path:)
          return [] unless path.end_with?(".rb")
          rel = relativize(path)
          return [] unless rel
          peers = neighbors(rel).reject { |peer, _| same_module?(rel, peer) }
                                .select { |_, w| w >= WEIGHT_THRESHOLD }
                                .sort_by { |_, w| -w }
                                .first(3)
          return [] if peers.empty?
          coupling_message = "co-changes with " + peers.map { |p, w| "#{p} (#{w}x)" }.join(", ")
          [finding(line: 1, message: coupling_message)]
        end

        private

        def neighbors(rel)
          graph[rel] || {}
        end

        def graph
          @graph_mutex.synchronize { @graph ||= build_graph }
        end

        COMMIT_SEPARATOR = "===commit===".freeze

        def build_graph
          out, _, status = Open3.capture3("git", "-C", repo_root,
                                          "log", "--name-only",
                                          "--pretty=format:#{COMMIT_SEPARATOR}",
                                          "-n", COMMITS_WINDOW.to_s, "--", "*.rb")
          return {} unless status.success?
          adjacency = Hash.new { |h, k| h[k] = Hash.new(0) }
          out.split(COMMIT_SEPARATOR).each do |chunk|
            files = chunk.lines.map(&:strip).reject(&:empty?).select { |f| f.end_with?(".rb") }
            next if files.size < 2 || files.size > MAX_FILES_IN_COMMIT
            files.combination(2) do |a, b|
              adjacency[a][b] += 1
              adjacency[b][a] += 1
            end
          end
          adjacency
        end

        def repo_root
          @repo_root ||= File.expand_path(File.join(Master::ROOT, ".."))
        end

        def relativize(path)
          full = File.expand_path(path)
          prefix = repo_root + "/"
          full.start_with?(prefix) ? full.delete_prefix(prefix) : nil
        end

        def same_module?(a, b) = module_of(a) == module_of(b)

        def module_of(path)
          parts = path.split("/")
          # MASTER/lib/<module>/... → use the module dir (judge/trace/etc.)
          parts[0] == "MASTER" ? (parts[2] || parts[0]) : parts[0]
        end
      end
    end
  end
  end
end
