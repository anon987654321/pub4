# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Trace
    module Ledger
      # Feedback mirrors high-signal execution feedback into the SQLite
      # knowledge store so RSI can inspect tool results, corrections, and provider failures.
      class Feedback
        def initialize(event_bus:, learnings:, rollback: nil)
          @bus = event_bus
          @learnings = learnings
          @rollback = rollback
        end

        def attach
          @bus&.subscribe("tool:after") { |payload| record_tool(payload) }
          @bus&.subscribe("llm:call_complete") { |payload| record_llm(payload) }
          @bus&.subscribe("llm:provider_outcome") { |payload| record_provider(payload) }
          @bus&.subscribe("user_correction") { |payload| record_user_correction(payload) }
          @bus&.subscribe("fix_loop:soul_proposal") { |payload| record_improvement(payload) }
          @bus&.subscribe("fix_loop:oscillation") { |_payload| trigger_rollback("fix loop oscillation") }
          @bus&.subscribe("fix_loop:cycle_detected") { |_payload| trigger_rollback("fix loop cycle detected") }
          self
        end

        private

        def record_tool(payload)
          dim = payload[:tool] || payload["tool"] || "unknown"
          value = payload[:exit_code] || payload["exit_code"]
          event_type = value.to_i.zero? ? "tool_success" : "tool_failure"
          record(event_type:, dimension: dim, value:, metadata: payload)
        end

        def record_llm(payload)
          model = payload[:model] || payload["model"] || "unknown"
          record(event_type: "tool_success", dimension: "llm:#{model}", value: payload[:tokens_out] || payload["tokens_out"], metadata: payload)
        end

        def record_provider(payload)
          status = (payload[:status] || payload["status"]).to_s
          model = payload[:model] || payload["model"] || "unknown"
          event_type = status == "success" ? "tool_success" : "provider_error"
          record(event_type:, dimension: model, value: status, metadata: payload)
        end

        def record_user_correction(payload)
          action = payload[:action] || payload["action"] || "unknown"
          record(event_type: "user_correction", dimension: action, metadata: payload)
        end

        def record(event_type:, dimension:, value: nil, metadata: nil)
          return unless @learnings&.respond_to?(:record_event)

          @learnings.record_event(
            event_type:,
            dimension:,
            value:,
            metadata: metadata && JSON.generate(metadata),
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.record", event_bus: @bus)
        end

        def record_improvement(payload)
          root = payload[:root] || payload["root"] || Master::ROOT
          rule_id = payload[:rule] || payload["rule"] || "unknown"
          files = Array(payload[:sample] || payload["sample"]).map { |row| row[:file] || row["file"] }.compact.uniq
          line = "#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files.join(", ")}\n"
          path = File.join(root, "runtime", "rsi_improvements.md")
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |file| file.write(line) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.record_improvement", event_bus: @bus)
        end

        def trigger_rollback(message)
          return unless @rollback

          error = Struct.new(:category, :message) do
            def err?
              true
            end
          end.new(:policy, message)
          @rollback.call(error)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.trigger_rollback", event_bus: @bus)
        end
      end

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

      # Tallies error:swallowed events per context — a spike in one context is a defect, not noise.
      class Swallow
        LEDGER_PATH = "runtime/swallow_ledger.jsonl"
        SNAPSHOT_EVERY = 50

        def initialize(event_bus:, root: Master::ROOT)
          @bus = event_bus
          @root = root
          @counts = Hash.new(0)
          @total = 0
          @mutex = Mutex.new
        end

        # Subscribe to the swallow stream. Call once at boot.
        #
        # `error:swallowed` is the topic Ground::Swallow.log publishes and
        # cognition/attention.rb weights. This read `swallow:error`, the same
        # two words the other way round, so the ledger that exists to make a
        # swallowed error visible had never counted one. Its test published the
        # subscriber's spelling on a fake bus, so both halves agreed with each
        # other and neither with the producer.
        def attach
          @bus&.subscribe("error:swallowed") { |payload| record(payload) }
          self
        end

        # context => count. Used by /axioms and tests.
        def snapshot = @mutex.synchronize { @counts.dup }

        def total = @mutex.synchronize { @total }

        private

        def record(payload)
          context = payload[:context] || payload["context"] || "unknown"
          flush if tally(context)
        end

        # Increment under lock; true when a snapshot flush is due.
        def tally(context)
          @mutex.synchronize do
            @counts[context] += 1
            @total += 1
            (@total % SNAPSHOT_EVERY).zero?
          end
        end

        def flush
          path = File.join(@root, LEDGER_PATH)
          FileUtils.mkdir_p(File.dirname(path))
          line = JSON.generate(at: Time.now.utc.iso8601, total:, counts: snapshot)
          File.open(path, "a") { |io| io.write(line, "\n") }
        rescue StandardError => e
          # Cannot route through Swallow.log — it recurses into this stream.
          ::Kernel.warn("swallow_ledger: flush failed — #{e.class}: #{e.message}")
        end
      end
    end
  end
end
