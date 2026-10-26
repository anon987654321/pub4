# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../execution/contract"
require_relative "../ground/redactor"
require "json"
require "time"
require "tempfile"

module Master
  module Trace
    module Ledger
      # Feedback mirrors high-signal execution feedback into the SQLite
      # knowledge store so RSI can inspect tool results, corrections, and provider failures.
      class Feedback
        SAFE_METADATA_FIELDS = %w[
          tool model status category exit_code bytes ms latency_ms tokens_in tokens_out
          cost cost_usd tokens cached cache_write estimated approximate count mode operation
          error_digest error_bytes files_count files_digest paths_count paths_digest
          url_digest url_bytes path_digest path_bytes query_digest query_bytes subject_digest subject_bytes
        ].freeze
        SENSITIVE_METADATA_FIELDS = %w[
          error message output result content prompt args input path paths file files url query
          subject stdout stderr body command argv headers cookie credential token authorization source
        ].freeze

        def initialize(event_bus:, learnings:)
          @bus = event_bus
          @learnings = learnings
        end

        # Set while one dispatcher call runs, once its tool has published its own
        # tool:after; the bus runs handlers inline, so the call, the tool and the
        # return are all on this thread.
        SELF_COUNTED = :master_ledger_tool_self_counted

        def attach
          @bus&.subscribe("tool:call") { |_payload| Thread.current[SELF_COUNTED] = nil }
          @bus&.subscribe("tool:after") do |payload|
            Thread.current[SELF_COUNTED] = tool_of(payload)
            record_tool(payload)
          end
          @bus&.subscribe("tool:return") { |payload| record_return(payload) }
          @bus&.subscribe("tool:failed") { |payload| record_tool_failure(payload) }
          @bus&.subscribe("llm:call_complete") { |payload| record_llm(payload) }
          @bus&.subscribe("llm:provider_outcome") { |payload| record_provider(payload) }
          @bus&.subscribe("fix_loop:soul_proposal") { |payload| record_improvement(payload) }
          @bus&.subscribe("ops:commit") { |payload| record_commit(payload) }
          self
        end

        private

        # tool:after is published on success, so it counts as one unless its own
        # outcome says otherwise: a non-zero exit, or an HTTP status of 400 and up.
        def record_tool(payload)
          dim = payload[:tool] || payload["tool"] || "unknown"
          exit_code = payload[:exit_code] || payload["exit_code"]
          status = (payload[:status] || payload["status"]).to_i
          event_type = exit_code.to_i.nonzero? || status >= 400 ? "tool_failure" : "tool_success"
          record(event_type:, dimension: dim, value: exit_code || status.nonzero?, metadata: safe_metadata(payload))
        end

        # read_file, list_dir, search_files and the other tools that publish no
        # tool:after were counted only when they failed, so /status read them as
        # failing every call. The dispatcher's tool:return counts their successes;
        # a tool that counted itself through tool:after is not counted twice.
        def record_return(payload)
          self_counted = Thread.current[SELF_COUNTED]
          Thread.current[SELF_COUNTED] = nil
          return unless (payload[:ok] || payload["ok"]) == true
          return if self_counted == tool_of(payload)

          record(event_type: "tool_success", dimension: tool_of(payload), metadata: safe_metadata(payload))
        end

        def tool_of(payload) = payload[:tool] || payload["tool"] || "unknown"

        # The learning store needs outcome telemetry, not raw tool inputs or
        # upstream output. Keep a small allow-list of operational dimensions and
        # fingerprint all content-bearing fields; unfamiliar future fields are
        # represented only by a digest of their names.
        def safe_metadata(payload)
          fields = payload.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
          result = { schema_version: 1 }

          SAFE_METADATA_FIELDS.each do |key|
            next unless fields.key?(key)

            value = fields[key]
            next if value.nil?
            next unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false || value.is_a?(Symbol)

            result[key.to_sym] = case value
            when String then Master::Ground::Redactor.truncate(Master::Ground::Redactor.text(value))
            when Symbol then value.to_s
            else value
            end
          end

          SENSITIVE_METADATA_FIELDS.each do |key|
            next unless fields.key?(key) && !fields[key].nil?

            begin
              raw = fields[key].is_a?(String) ? fields[key] : JSON.generate(fields[key])
              result.merge!(Master::Execution::Contract.diagnostic_fields(raw, key: key.to_sym))
            rescue StandardError
              result[:"#{key}_present"] = true
            end
          end

          extra_keys = fields.keys - SAFE_METADATA_FIELDS - SENSITIVE_METADATA_FIELDS - %w[event ts conversation]
          unless extra_keys.empty?
            result[:extra_fields_count] = extra_keys.size
            result[:extra_fields_digest] = Digest::SHA256.hexdigest(extra_keys.sort.join("\0"))
          end
          result
        end

        def record_tool_failure(payload)
          dim = payload[:tool] || payload["tool"] || "unknown"
          category = (payload[:category] || payload["category"]).to_s
          record(event_type: "tool_failure", dimension: dim, value: category, metadata: safe_metadata(payload))
        end

        def record_llm(payload)
          model = payload[:model] || payload["model"] || "unknown"
          record(event_type: "tool_success", dimension: "llm:#{model}", value: payload[:tokens_out] || payload["tokens_out"], metadata: safe_metadata(payload))
        end

        def record_provider(payload)
          status = (payload[:status] || payload["status"]).to_s
          model = payload[:model] || payload["model"] || "unknown"
          event_type = status == "success" ? "tool_success" : "provider_error"
          record(event_type:, dimension: model, value: status, metadata: safe_metadata(payload))
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
          law_id = payload[:law] || payload["law"] || "unknown"
          files = Array(payload[:sample] || payload["sample"]).filter_map { |row| row[:file] || row["file"] }.uniq
          record(
            event_type: "fix_improvement",
            dimension: law_id,
            value: files.size,
            metadata: {
              schema_version: 1, files_count: files.size,
              **Master::Execution::Contract.diagnostic_fields(files.sort.join("\0"), key: :files)
            },
          )

        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.record_improvement", event_bus: @bus)
        end

        def record_commit(payload)
          root = payload[:root] || payload["root"] || Master::ROOT
          paths = Array(payload[:paths] || payload["paths"])
          Master::Phoenix.record_commit(
            root:,
            message: payload[:message] || payload["message"],
            head: payload[:head] || payload["head"],
            paths:,
            findings: payload[:findings] || payload["findings"] || [],
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.record_commit", event_bus: @bus)
        end
      end

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

          # Optimized: avoid creating intermediate array from .last()
          # Read in reverse and take first N, filtering as we go
          File.readlines(@path).reverse.first(limit).filter_map { |line| parse_reflection(line) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Reflexion.recent", event_bus: @bus)
          []
        end

        private

        def record(payload, kind)
          raw_reason = (payload[:reason] || payload["reason"] || kind).to_s
          raw_files = Array(payload[:files] || payload["files"]).map { |file| File.basename(file.to_s) }.uniq
          reason = Master::Ground::Redactor.truncate(Master::Ground::Redactor.text(raw_reason))
          files = raw_files.map { |file| Master::Ground::Redactor.truncate(Master::Ground::Redactor.text(file)) }.uniq
          reason_evidence = Master::Execution::Contract.diagnostic_fields(raw_reason)
          file_evidence = Master::Execution::Contract.diagnostic_fields(raw_files.sort.join("\\0"), key: :files)
          append(
            {
              "ts" => Time.now.utc.iso8601, "kind" => kind, "reason" => reason, "files" => files,
              "reason_digest" => reason_evidence[:error_digest],
              "reason_bytes" => reason_evidence[:error_bytes],
              "files_count" => files.size,
              "files_digest" => file_evidence[:files_digest],
              "reflection" => sentence(kind, reason, files)
            }
          )
          @bus&.publish(
            "reflexion:recorded", kind:,
            reason_digest: reason_evidence[:error_digest], reason_bytes: reason_evidence[:error_bytes],
            files_count: files.size, files_digest: file_evidence[:files_digest]
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Reflexion.record", event_bus: @bus)
        end

        def sentence(kind, reason, files)
          where = files.empty? ? "" : " in #{files.join(", ")}"
          "commit #{kind} (#{reason})#{where} — re-read these files and resolve #{reason} before retrying"
        end

        def append(entry)
          directory = File.dirname(@path)
          FileUtils.mkdir_p(directory)
          lock_path = "#{@path}.lock"
          raise IOError, "reflexion lock is a symlink" if File.symlink?(lock_path)

          File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
            File.chmod(0o600, lock_path)
            lock.flock(File::LOCK_EX)
            raise IOError, "reflexion log is a symlink" if File.symlink?(@path)

            kept = if File.file?(@path)
              stat = File.lstat(@path)
              raise IOError, "reflexion log is not a regular file" unless stat.file? && !stat.symlink?

              File.chmod(0o600, @path)
              File.readlines(@path).last(MAX_REFLECTIONS - 1)
            else
              []
            end
            content = (kept << "#{JSON.generate(entry)}\n").join
            Tempfile.create(["reflexions-", ".tmp"], directory, binmode: true) do |temporary|
              temporary.write(content)
              temporary.flush
              temporary.fsync
              temporary.close
              File.chmod(0o600, temporary.path)
              File.rename(temporary.path, @path)
            end
          ensure
            lock.flock(File::LOCK_UN) if lock
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Reflexion.append", event_bus: @bus)
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
          # Cannot route through Swallow.log — it would recurse into this stream.
          Master::Trace::Dmesg.once("error0", "ledger flush failed, #{e.class}: #{e.message}")
        end
      end
    end
  end
end
