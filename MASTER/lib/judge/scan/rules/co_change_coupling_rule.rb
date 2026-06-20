# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules
        # Files that change together in many commits are coupled regardless of imports.
        # Reads the co-change graph from RepoEcology (built once at boot) instead of
        # mining git per-scan. Flags cross-module pairs — likely DECOUPLE candidates
        # the lexical rules can't see.
        class CoChangeCouplingRule < Rule
          WEIGHT_THRESHOLD = 5

          def self.auto_build? = false

          def initialize(root: nil, ecology: nil)
            super()
            @id = "co_change_coupling"
            @description = "Files co-change with N+ peers across module boundaries — hidden coupling"
            @severity = :info
            @rule_tags = %i[DECOUPLE ONE_JOB]
            @root = root ? File.expand_path(root) : File.expand_path(File.join(Master::ROOT, ".."))
            @ecology = ecology
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb")

            rel = relativize(path)
            return [] unless rel

            peers = neighbors(rel)
              .reject { |peer, _| same_module?(rel, peer) }
              .select { |_, weight| weight >= WEIGHT_THRESHOLD }
              .sort_by { |_, weight| -weight }
              .take(3)
              .to_a
            return [] if peers.empty?

            [finding(line: 1, message: coupling_message(rel, peers))]
          end

          private

          def coupling_message(rel, peers)
            names = peers.map { |peer, weight| "#{peer} (#{weight})" }.join(", ")
            "co-changes across modules with #{peers.size} peer(s): #{names} — #{rel}"
          end

          def neighbors(rel)
            graph[rel] || {}
          end

          def graph
            @ecology ? @ecology.co_change_graph : {}
          end

          def relativize(path)
            full = File.expand_path(path)
            prefix = @root + "/"
            full.start_with?(prefix) ? full.delete_prefix(prefix) : nil
          end

          def same_module?(a, b) = module_of(a) == module_of(b)

          def module_of(path)
            parts = path.split("/")
            parts[0] == "MASTER" ? (parts[2] || parts[0]) : parts[0]
          end
        end
      end
    end
  end
end