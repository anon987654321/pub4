# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../../ground/swallow"

module Master
  module Trace
    module Ledger
      # Reflexion captures fix-loop self-correction failures as natural-language
      # reflections (Reflexion-style episodic memory) so later attempts avoid repeating a
      # blocked commit. Refs: Shinn et al. Reflexion (arXiv:2303.11366); ReVeal (arXiv:2506.11442).
      class Reflexion
        MAX_REFLECTIONS = 50

        def initialize(event_bus:, root: Master::ROOT)
          @bus = event_bus
          @path = File.join(root, "runtime", "reflexions.ndjson")
        end

        def attach
          @bus&.subscribe("fix_loop:commit_blocked") { |payload| record(payload, "blocked") }
          @bus&.subscribe("fix_loop:commit_error") { |payload| record(payload, "error") }
          self
        end

        # Newest-first natural-language reflections to inject into the next fix attempt.
        def recent(limit = 5)
          return [] unless File.exist?(@path)

          File.readlines(@path).last(limit).reverse.filter_map { |line| parse_reflection(line) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Reflexion.recent", event_bus: @bus)
          []
        end

        private

        def record(payload, kind)
          reason = (payload[:reason] || payload["reason"] || kind).to_s
          files = Array(payload[:files] || payload["files"]).map { |f| File.basename(f.to_s) }.uniq
          append("ts" => Time.now.utc.iso8601, "kind" => kind, "reason" => reason,
                 "files" => files, "reflection" => sentence(kind, reason, files))
          @bus&.publish("reflexion:recorded", reason:, files:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Reflexion.record", event_bus: @bus)
        end

        def sentence(kind, reason, files)
          where = files.empty? ? "" : " in #{files.join(", ")}"
          "commit #{kind} (#{reason})#{where} — re-read these files and resolve #{reason} before retrying"
        end

        def append(entry)
          FileUtils.mkdir_p(File.dirname(@path))
          lines = File.exist?(@path) ? File.readlines(@path) : []
          lines.push(JSON.generate(entry) + "\n")
          File.write(@path, lines.last(MAX_REFLECTIONS).join)
        end

        def parse_reflection(line)
          JSON.parse(line)["reflection"]
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Reflexion.parse_reflection")
          nil
        end
      end
    end
  end
end
