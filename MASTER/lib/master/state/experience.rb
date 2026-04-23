# frozen_string_literal: true

require "json"
require "digest"

module Master
  module State
    # Experience store — records (plan → outcome) pairs across runs.
    #
    # Used by future PlanTree/MCTS stages (not wired in this patch) to bias
    # plan selection toward sequences that have succeeded before.
    # Minimal drop-in: no vector DB, no embeddings, exact-match on plan
    # signature. Adding embedding-based similarity is a later step.
    #
    # Design follows the ChatGPT-session sketch with two critical additions:
    #   1. Score decay (0.99 per record) to avoid permanent lock-in on
    #      plans that were good once and wouldn't be now.
    #   2. Small exploration noise added at read time so novel plans aren't
    #      permanently dominated by historically successful ones.
    #
    # File format: JSON at .master/experience.json, keyed by plan signature.
    class Experience
      DECAY        = 0.99
      EXPLORE_NOISE = 0.05   # ±5% random perturbation on recall

      def initialize(root:)
        @path = File.join(root, ".master", "experience.json")
        FileUtils.mkdir_p(File.dirname(@path))
      end

      # Record the outcome of a plan. `plan` is any array-of-hashes or
      # array-of-symbols; we derive a stable signature from it.
      # `score` should be roughly in [-1.0, +1.0].
      def record(plan:, score:)
        data = load_data
        key  = signature(plan)
        entry = data[key] ||= { "count" => 0, "sum" => 0.0, "updated_at" => 0 }

        entry["sum"]        = (entry["sum"] * DECAY) + score.to_f
        entry["count"]      = (entry["count"] * DECAY) + 1
        entry["updated_at"] = Time.now.to_i

        write_data(data)
        entry
      end

      # Return the decayed-average score for a plan, with a small amount
      # of exploration noise so novel candidates can still win.
      def score(plan)
        data = load_data
        entry = data[signature(plan)]
        base  = entry ? (entry["sum"] / [entry["count"], 1.0].max) : 0.0
        base + ((rand * 2.0) - 1.0) * EXPLORE_NOISE
      end

      # Opportunity: retrieve top-N plans by recent average score.
      def top(limit: 5)
        data = load_data
        data.filter_map { |sig, e|
          next if e["count"].to_f.zero?
          [sig, e["sum"] / e["count"]]
        }.sort_by { |_, avg| -avg }.first(limit)
      end

      def clear!
        File.delete(@path) if File.exist?(@path)
        self
      end

      private

      # Stable plan signature — only the sequence of tool identifiers.
      # Ignores arguments on purpose: "fs_read → ast_replace → git_commit"
      # is the same strategy whether it edited user.rb or auth.rb.
      def signature(plan)
        tools = Array(plan).map { |step|
          case step
          when Hash   then (step[:tool] || step["tool"]).to_s
          when Symbol then step.to_s
          else             step.to_s
          end
        }
        Digest::SHA256.hexdigest(tools.join("->"))[0, 16]
      end

      def load_data
        return {} unless File.exist?(@path)
        JSON.parse(File.read(@path))
      rescue JSON::ParserError
        {}
      end

      def write_data(data)
        File.write(@path, JSON.generate(data))
      end
    end
  end
end
