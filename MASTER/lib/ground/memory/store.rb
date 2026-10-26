# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../cognition/intelligence"

module Master
  module Ground
    class Memory
      # Memory's session store: typed entries in .master/memory.yml, pruned and
      # consolidated in place. SqliteStore opens the databases, KnowledgeStore
      # records fix outcomes, and neither holds a conversation's memory.
      module Store
        include ::Master::Io::AtomicWrite

        def initialize(root: Dir.pwd)
          @root = root
          @path = File.join(root, ".master", "memory.yml")
          @mutex = Mutex.new
          @store = load_store
          @store_version = 0
          import_external!
        end

        def remember(key, value, type: "general", source: nil, confidence: 0.5, embed: true)
          type = TYPES.include?(type.to_s) ? type.to_s : "general"
          source ||= caller_source
          confidence = confidence.to_f.clamp(0.0, 1.0)
          @mutex.synchronize do
            prune_stale! if @store.size > CONSOLIDATE_THRESHOLD
            previous = @store[key.to_s]
            entry = entry_for(key:, value:, type:, source:, confidence:, embed:)
            record_conflict!(key.to_s, previous, entry) if conflicting_entry?(key.to_s, previous, entry)
            @store[key.to_s] = entry
            persist
          end
        end

        # Structured reasoning shares the durable memory store but skips
        # embedding: causal frames are control data, not semantic documents.
        def remember_preference(frame, key: nil)
          row = frame.respond_to?(:to_h) ? frame.to_h : frame
          return unless row.is_a?(Hash) && !row.empty?

          payload = JSON.generate(stringify_keys(row))
          digest = Digest::SHA256.hexdigest(payload)[0, 12]
          memory_key = key.to_s.empty? ? "preference/#{Time.now.to_i}-#{digest}" : key.to_s
          remember(
            memory_key,
            payload,
            type: "feedback",
            source: row[:source] || row["source"] || "cognition:taste",
            confidence: row[:confidence] || row["confidence"] || 0.5,
            embed: false,
          )
          memory_key
        end

        def preferences(limit: 8)
          rows = by_type("feedback").filter_map do |key, entry|
            next unless key.to_s.start_with?("preference/", "auto/feedback/")
            body = entry.is_a?(Hash) ? entry["value"] : entry
            parsed = JSON.parse(body.to_s)
            parsed.merge("_key" => key)
          rescue JSON::ParserError
            nil
          end
          rows.first(limit.to_i)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.preferences")
          []
        end

        def remember_reasoning(frame, key: nil)
          row = frame.respond_to?(:to_h) ? frame.to_h : frame
          return unless row.is_a?(Hash) && !row.empty?

          payload = JSON.generate(stringify_keys(row))
          digest = Digest::SHA256.hexdigest(payload)[0, 12]
          memory_key = key.to_s.empty? ? "reasoning/#{Time.now.to_i}-#{digest}" : key.to_s
          remember(
            memory_key,
            payload,
            type: "reasoning",
            source: "cognition:intelligence",
            confidence: row[:confidence] || row["confidence"] || 0.5,
            embed: false,
          )
          memory_key
        end

        def reasoning(limit: 8)
          rows = by_type("reasoning").filter_map do |key, entry|
            body = entry.is_a?(Hash) ? entry["value"] : entry
            parsed = JSON.parse(body.to_s)
            parsed.merge("_key" => key, "_ts" => entry.is_a?(Hash) ? entry["ts"].to_i : 0)
          rescue JSON::ParserError
            nil
          end
          rows.sort_by { |row| -row["_ts"].to_i }.first(limit.to_i)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.reasoning")
          []
        end

        # Reviews affect context eligibility without erasing the original memory.
        # Contradicted/obsolete entries remain auditable through #recall.
        def review(key, verdict:, evidence:, reviewer:)
          verdict = verdict.to_s
          allowed = %w[confirmed contradicted uncertain obsolete]
          raise ArgumentError, "unknown memory review verdict: #{verdict}" unless allowed.include?(verdict)

          receipt = Master::Cognition::OutcomeModel.validate_evidence!(evidence, root: @root)
          reviewer = reviewer.to_s.strip
          raise ArgumentError, "reviewer is required" if reviewer.empty?

          @mutex.synchronize do
            stored = @store[key.to_s]
            return nil if stored.nil?
            return nil if stored.is_a?(Hash) && !stored.key?("value")

            # Older stores may still contain a plain scalar. Promote it without
            # changing the recalled text so a review can govern it safely too.
            entry = if stored.is_a?(Hash)
              stored
            else
              @store[key.to_s] = { "value" => stored.to_s, "ts" => 0, "type" => "general" }
            end

            prior = entry["provenance"]
            provenance = prior.is_a?(Hash) ? prior.dup : legacy_provenance(entry)
            reviews = Array(provenance["reviews"]).select { |row| row.is_a?(Hash) }
            reviews << {
              "verdict" => verdict,
              "source" => receipt.fetch("source"),
              "sha256" => receipt.fetch("sha256"),
              "reviewer" => reviewer[0, 120],
              "reviewed_at" => Time.now.utc.iso8601,
            }
            provenance["reviews"] = reviews.last(8)
            provenance["status"] = verdict
            provenance["reviewed_at"] = reviews.last.fetch("reviewed_at")
            entry["provenance"] = provenance
            # A consolidated summary may repeat a fact now marked obsolete.
            # Invalidate both its durable copy and the in-memory summary.
            @store.delete("_consolidated_summary")
            @context_summary_cache = nil
            persist
            provenance.dup
          end
        end

        def context_eligible?(key, entry = nil)
          name = key.to_s
          return false if name.start_with?("archive/", "conflict/") || name == "_consolidated_summary"

          row = entry
          row = @mutex.synchronize { @store[name] } if row.nil?
          return false if row.nil?
          return true unless row.is_a?(Hash)

          provenance = row["provenance"]
          status = provenance.is_a?(Hash) ? provenance["status"].to_s : ""
          !%w[contradicted obsolete].include?(status)
        end

        def provenance(key)
          @mutex.synchronize do
            value = @store[key.to_s]
            value.is_a?(Hash) ? (value["provenance"] || legacy_provenance(value)) : nil
          end
        end

        def conflicts_for(key)
          prefix = "conflict/#{key}/"
          @mutex.synchronize do
            @store.filter_map do |conflict_key, value|
              next unless conflict_key.to_s.start_with?(prefix)
              value
            end.sort_by { |value| -value["ts"].to_i }
          end
        end

        def by_type(type)
          @mutex.synchronize do
            @store.select do |key, value|
              typed_entry?(key:, value:, type: type.to_s) && context_eligible?(key, value)
            end
          end
        end

        def type_counts
          @mutex.synchronize do
            @store.each_with_object(Hash.new(0)) do |(key, value), counts|
              next if archived_or_summary?(key)

              counts[value.is_a?(Hash) ? (value["type"] || "general") : "general"] += 1
            end
          end
        end

        # The local operator's words only. A web visitor's "I am a..." was saved as
        # explicit operator feedback and read into every later prompt, the operator's too.
        def auto_save(text)
          return if text.to_s.empty? || Fiber[:master_visitor] == true

          AUTO_SAVE_PATTERNS.each do |type, pattern|
            next unless (match = text.match(pattern))

            return remember_auto(type, match[1].strip)
          end
          nil
        end

        def recall(key)
          @mutex.synchronize { @store.dig(key.to_s, "value") }
        end

        # Explicit forgetting removes every retained copy owned by this key,
        # including archived entries and contradiction records. It does not
        # affect unrelated keys that merely share a prefix.
        def forget(key)
          name = key.to_s
          @mutex.synchronize do
            @store.delete_if do |stored_key, _|
              path = stored_key.to_s
              path == name || path == "archive/#{name}" || path == "_consolidated_summary" ||
                path.start_with?("conflict/#{name}/", "archive/conflict/#{name}/")
            end
            @context_summary_cache = nil
            persist
          end
        end

        def all
          @mutex.synchronize { @store.transform_values { |value| value.is_a?(Hash) ? value["value"] : value } }
        end

        def version
          File.file?(@path) ? Digest::SHA256.file(@path).hexdigest[0, 16] : "empty"
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.version")
          "unknown"
        end

        private

        def store_version
          @mutex.synchronize { @store_version }
        end

        def entry_for(key:, value:, type:, source:, confidence:, embed: true)
          ts = Time.now.to_i
          entry = {
            "value" => value.to_s,
            "ts" => ts,
            "type" => type,
            "provenance" => {
              "source" => source.to_s,
              "captured_at" => ts,
              "confidence" => confidence,
            },
          }
          entry["vec"] = vec if embed && (vec = Review::Embeddings.embed("#{key} #{value}"))
          entry
        end

        def stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) { |(key, item), out| out[key.to_s] = stringify_keys(item) }
          when Array
            value.map { |item| stringify_keys(item) }
          when Symbol then value.to_s
          else value
          end
        end

        def caller_source
          location = caller_locations(2, 1).first
          return "runtime" unless location

          path = location.path.to_s
          relative = path.start_with?("#{Master::ROOT}/") ? path.delete_prefix("#{Master::ROOT}/") : File.basename(path)
          "runtime:#{relative}:#{location.lineno}"
        end

        def legacy_provenance(value)
          {
            "source" => "legacy",
            "captured_at" => value["ts"].to_i,
            "confidence" => 0.0,
          }
        end

        def conflicting_entry?(key, previous, entry)
          return false if key == "_consolidated_summary"
          return false unless previous.is_a?(Hash) && previous.key?("value")

          previous["value"].to_s != entry["value"].to_s
        end

        def record_conflict!(key, previous, entry)
          fingerprint = Digest::SHA256.hexdigest("#{key}\0#{entry["value"]}")[0, 12]
          conflict_key = "conflict/#{key}/#{entry["ts"]}-#{fingerprint}"
          @store[conflict_key] = {
            "key" => key,
            "previous" => previous["value"].to_s,
            "incoming" => entry["value"].to_s,
            "previous_provenance" => previous["provenance"] || legacy_provenance(previous),
            "incoming_provenance" => entry["provenance"],
            "ts" => entry["ts"],
          }
        end

        def typed_entry?(key:, value:, type:)
          value.is_a?(Hash) && value["type"] == type && !key.start_with?("archive/")
        end

        def archived_or_summary?(key)
          key.to_s.start_with?("archive/", "conflict/") || key == "_consolidated_summary"
        end

        def remember_auto(type, snippet)
          return if snippet.length < 3

          digest = Digest::SHA256.hexdigest(snippet.downcase)[0, 12]
          key = "auto/#{type}/#{digest}"
          if type == "feedback"
            frame = Master::Cognition::Intelligence.preference_frame(
              domain: "operator",
              preference: snippet,
              evidence: "explicit operator feedback",
              source: "auto_save",
            )
            remember_preference(frame, key:)
          else
            remember(key, snippet, type:, source: "auto_save")
          end
          key
        end

        def import_external!
          import_brain_files!
          import_project_context!
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.preload_context")
        end

        def import_project_context!
          path = File.join(@root, "data", "project_context.yml")
          return unless File.file?(path)

          data = Master.load_yaml(path)
          Array(data["entries"]).each do |entry|
            next unless entry.is_a?(Hash)

            key = "claude/#{entry["key"]}"
            next if @store.key?(key)

            body = entry["body"].to_s.strip
            remember(key, body, type: entry["type"].to_s, source: "data/project_context.yml") unless body.empty?
          end
        end

        def import_brain_files!
          %w[IDENTITY.md SOUL.md].each do |name|
            path = File.join(@root, "data", name)
            next unless File.exist?(path)

            key = "brain/#{File.basename(name, ".md").downcase}"
            next if @store.key?(key)

            body = File.read(path, encoding: "UTF-8").strip
            remember(key, body, type: brain_type(name), source: "data/#{name}") unless body.empty?
          end
        end

        def brain_type(name)
          case name
          when "MEMORY.md" then "user"
          when "TOOLS.md" then "reference"
          else "general"
          end
        end

        def prune_stale!
          cutoff = Time.now.to_i - TTL_DAYS * SECONDS_PER_DAY
          @store.to_a.each do |key, value|
            next if archived_or_summary?(key)
            next unless stale_entry?(value, cutoff)

            @store["archive/#{key}"] = @store.delete(key)
          end
        end

        def stale_entry?(value, cutoff)
          ts = value.is_a?(Hash) ? value["ts"].to_i : 0
          ts.positive? && ts < cutoff
        end

        def load_store
          return {} unless File.exist?(@path)

          loaded = Master.load_yaml(@path)
          loaded.is_a?(Hash) ? loaded : {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "memory.load_store", path: @path)
          {}
        end

        def persist
          FileUtils.mkdir_p(File.dirname(@path))
          write_atomic(@path, @store.to_yaml, mode: 0o600)
          @store_version += 1
        end
      end
    end
  end
end
