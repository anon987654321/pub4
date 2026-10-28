# frozen_string_literal: true

module Master
  module Cognition
    # Durable internal state. Numeric attention/activity values are operational
    # proxies, not measures of phenomenal consciousness. Restore completeness is
    # calculated from the saved schema before defaults are merged in.
    class State
      PATH = ".master/cognition/state.yml"
      MAX_PREDICTION_ANTECEDENTS = 64
      MAX_PREDICTION_SUCCESSORS = 16
      MAX_PREDICTION_STREAMS = 32
      MAX_PERFORMANCE_BUCKETS = 32
      IDENTIFIER_PATTERN = /\A[a-z0-9_.:-]{1,80}\z/

      DEFAULT = {
        "identity" => { "name" => "MASTER", "agency" => 0.5, "coherence" => 1.0 },
        "affect" => { "valence" => 0.0, "arousal" => 0.25, "novelty" => 0.0, "uncertainty" => 0.5 },
        "drives" => { "safety" => 1.0, "coherence" => 0.8, "curiosity" => 0.6, "agency" => 0.5, "affiliation" => 0.4 },
        "workspace" => [],
        "predictions" => { "transitions" => {}, "previous_event" => nil, "last_error" => 0.0 },
        "outcomes" => { "records" => {} },
        "self_model" => {},
        "thoughts" => [],
        "metrics" => { "workspace_activity" => 0.0, "prediction_error" => 0.0, "restore_completeness" => 0.0, "attention" => 0.0 },
        "last_tick_at" => 0,
        "ticks" => 0,
      }.freeze

      MAX_WORKSPACE = 12
      MAX_THOUGHTS = 20

      class << self
        def load(path)
          return new({}, load_status: "new") unless File.file?(path)

          raw = Master.load_yaml(path)
          return new({}, load_status: "invalid") unless raw.is_a?(Hash)

          completeness = schema_completeness(raw)
          return new({}, load_status: "invalid", restore_completeness: completeness) unless schema_compatible?(raw, DEFAULT)

          new(raw, load_status: "restored", restore_completeness: completeness)
        rescue StandardError
          new({}, load_status: "invalid")
        end

        def schema_completeness(raw)
          present, expected = schema_coverage(raw, DEFAULT)
          return 0.0 unless expected.positive?

          (present.to_f / expected).round(4)
        end

        def schema_coverage(actual, expected)
          if expected.is_a?(Hash)
            return [actual.is_a?(Hash) ? 1 : 0, 1] if expected.empty?

            present = 0
            total = 0
            expected.each do |key, shape|
              child_present, child_total = if actual.is_a?(Hash) && actual.key?(key)
                                             schema_coverage(actual[key], shape)
                                           else
                                             [0, schema_size(shape)]
                                           end
              present += child_present
              total += child_total
            end
            [present, total]
          else
            compatible = case expected
                         when Array then actual.is_a?(Array)
                         when Numeric then actual.is_a?(Numeric)
                         when String then actual.is_a?(String)
                         when TrueClass, FalseClass then actual == true || actual == false
                         when NilClass then actual.nil? || actual.is_a?(String)
                         else actual.class == expected.class
                         end
            [compatible ? 1 : 0, 1]
          end
        end

        # Existing keys must retain the type the cognitive code expects. Missing
        # keys are a schema migration; malformed present values are not safe to
        # deep-merge and later treat as a valid restoration.
        def schema_compatible?(actual, expected)
          case expected
          when Hash
            return false unless actual.is_a?(Hash)
            return false unless expected.all? { |key, shape| !actual.key?(key) || schema_compatible?(actual[key], shape) }

            return valid_predictions?(actual) if expected.equal?(DEFAULT["predictions"])
            return valid_self_model?(actual) if expected.equal?(DEFAULT["self_model"])
            return valid_outcomes?(actual) if expected.equal?(DEFAULT["outcomes"])
            true
          when Array
            return false unless actual.is_a?(Array)
            return valid_workspace?(actual) if expected.equal?(DEFAULT["workspace"])
            return valid_thoughts?(actual) if expected.equal?(DEFAULT["thoughts"])

            true
          when Numeric then actual.is_a?(Numeric) && actual.to_f.finite?
          when String then actual.is_a?(String)
          when TrueClass, FalseClass then actual == true || actual == false
          when NilClass then actual.nil? || actual.is_a?(String)
          else actual.class == expected.class
          end
        end

        def valid_predictions?(predictions)
          return false if predictions.key?("previous_event") && !nullable_string?(predictions["previous_event"])
          return false if predictions.key?("last_error") && !finite_number?(predictions["last_error"])
          return false if predictions.key?("observations") && !(predictions["observations"].is_a?(Integer) && predictions["observations"] >= 0)
          return false if predictions.key?("transitions") && !valid_transition_table?(predictions["transitions"])
          return true unless predictions.key?("streams")

          streams = predictions["streams"]
          streams.is_a?(Hash) && streams.size <= MAX_PREDICTION_STREAMS && streams.all? do |key, stream|
            key.is_a?(String) && stream.is_a?(Hash) &&
              (!stream.key?("previous_event") || nullable_string?(stream["previous_event"])) &&
              (!stream.key?("last_error") || finite_number?(stream["last_error"])) &&
              (!stream.key?("observations") || (stream["observations"].is_a?(Integer) && stream["observations"] >= 0)) &&
              (!stream.key?("last_observed_at") || stream["last_observed_at"].is_a?(Integer)) &&
              (!stream.key?("transitions") || valid_transition_table?(stream["transitions"]))
          end
        end

        # A corrupt record would train every later prediction, so one malformed
        # row rejects the section, as it does for predictions.
        def valid_outcomes?(outcomes)
          records = outcomes["records"]
          return false unless records.is_a?(Hash) && records.size <= 256

          records.all? do |key, record|
            next false unless key.is_a?(String) && key.match?(/\A[0-9a-f]{24}\z/) && record.is_a?(Hash)
            next false unless %w[context action].all? { |field| record[field].is_a?(String) && !record[field].empty? }

            counters_valid = %w[successes failures inconclusive brier_count].all? do |counter|
              value = record.fetch(counter, 0)
              value.is_a?(Integer) && value >= 0
            end
            next false unless counters_valid
            brier_sum = record.fetch("brier_sum", 0.0)
            next false unless finite_number?(brier_sum) && brier_sum.to_f >= 0.0

            observations = record.fetch("observations", [])
            receipts = record.fetch("seen_receipts", [])
            next false unless observations.is_a?(Array) && observations.size <= 12
            next false unless receipts.is_a?(Array) && receipts.size <= 64

            observations_valid = observations.all? do |item|
              item.is_a?(Hash) &&
                %w[success failure inconclusive].include?(item["outcome"]) &&
                item["source"].is_a?(String) &&
                item["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
                (item["predicted_probability"].nil? ||
                  (finite_number?(item["predicted_probability"]) && item["predicted_probability"].between?(0.0, 1.0))) &&
                item["observed_at"].is_a?(String)
            end
            next false unless observations_valid

            receipts.all? do |item|
              item.is_a?(Hash) && item["source"].is_a?(String) &&
                item["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
                %w[success failure inconclusive].include?(item["outcome"])
            end
          end
        end

        def valid_transition_table?(table)
          table.is_a?(Hash) && table.size <= MAX_PREDICTION_ANTECEDENTS && table.all? do |previous, successors|
            previous.is_a?(String) && successors.is_a?(Hash) && successors.size <= MAX_PREDICTION_SUCCESSORS &&
              successors.all? { |event, count| event.is_a?(String) && count.is_a?(Integer) && count >= 0 }
          end
        end

        def valid_workspace?(workspace)
          workspace.size <= MAX_WORKSPACE && workspace.all? do |item|
            item.is_a?(Hash) &&
              (!item.key?("key") || item["key"].is_a?(String)) &&
              (!item.key?("event") || item["event"].is_a?(String)) &&
              (!item.key?("salience") || finite_number?(item["salience"])) &&
              (!item.key?("prediction_error") || finite_number?(item["prediction_error"])) &&
              (!item.key?("at") || item["at"].is_a?(Integer))
          end
        end

        def valid_thoughts?(thoughts)
          thoughts.size <= MAX_THOUGHTS && thoughts.all? do |thought|
            thought.is_a?(Hash) &&
              (!thought.key?("text") || thought["text"].is_a?(String)) &&
              (!thought.key?("kind") || thought["kind"].is_a?(String)) &&
              (!thought.key?("at") || thought["at"].is_a?(Integer))
          end
        end

        def valid_self_model?(model)
          return false if model.key?("capabilities") && !model["capabilities"].is_a?(Hash)
          return false if model.key?("last_payload") && !model["last_payload"].is_a?(Hash)
          return false if model.key?("last_event") && !model["last_event"].is_a?(String)
          return false if model.key?("performance") && !model["performance"].is_a?(Hash)

          model.all? do |key, value|
            if key.to_s.start_with?("event/")
              value.is_a?(Hash) && (!value.key?("salience") || finite_number?(value["salience"])) &&
                (!value.key?("count") || (value["count"].is_a?(Integer) && value["count"] >= 0)) &&
                (!value.key?("last_at") || value["last_at"].is_a?(Integer))
            elsif key == "performance" && value.is_a?(Hash)
              value.size <= MAX_PERFORMANCE_BUCKETS && value.all? do |name, row|
                name.is_a?(String) && IDENTIFIER_PATTERN.match?(name) && row.is_a?(Hash) &&
                  %w[attempts successes failures confidence_observations].all? do |field|
                    !row.key?(field) || (row[field].is_a?(Integer) && row[field] >= 0)
                  end &&
                  %w[confidence_sum brier_sum].all? do |field|
                    !row.key?(field) || finite_number?(row[field])
                  end &&
                  (!row.key?("last_at") || row["last_at"].is_a?(Integer))
              end
            else
              true
            end
          end
        end

        def nullable_string?(value) = value.nil? || value.is_a?(String)

        def finite_number?(value) = value.is_a?(Numeric) && value.to_f.finite?

        def schema_size(shape)
          return 1 unless shape.is_a?(Hash) && !shape.empty?

          shape.values.sum { |value| schema_size(value) }
        end

        def deep_dup(value)
          case value
          when Hash then value.to_h { |key, inner| [key, deep_dup(inner)] }
          when Array then value.map { |item| deep_dup(item) }
          else value
          end
        end

        def deep_merge(left, right)
          left.merge(right) do |_key, ours, theirs|
            ours.is_a?(Hash) && theirs.is_a?(Hash) ? deep_merge(ours, theirs) : theirs
          end
        end
      end

      attr_reader :data, :load_status, :restore_completeness

      # DEFAULT is frozen and deep_dup'd on the way in, so a caller that passes
      # DEFAULT itself still gets a mutable state rather than a FrozenError two
      # layers down. Restoration metadata describes the source state, not an
      # inferred degree of consciousness or personal identity.
      def initialize(data, load_status: "new", restore_completeness: 0.0)
        @load_status = load_status.to_s
        @restore_completeness = restore_completeness.to_f.clamp(0.0, 1.0)
        @data = self.class.deep_merge(self.class.deep_dup(DEFAULT), data)
        migrate_proxy_metrics!
      end

      # These old fields were formula-driven placeholders, not measurements. Drop
      # them during the in-memory schema migration instead of exposing stale values.
      def migrate_proxy_metrics!
        @data["identity"].delete("continuity") if @data["identity"].is_a?(Hash)
        return unless @data["metrics"].is_a?(Hash)
          @data["metrics"].delete("continuity")
          @data["metrics"].delete("integration")

      end

      # One reader per section of the schema, from the schema. Nine of these were
      # written out, each `@data.fetch("<its own name>")`, which is the same
      # method nine times and put the class over the god-class ceiling on nothing
      # but transcription. Generating them keeps DEFAULT the single statement of
      # what a state has: add a section there and its reader exists.
      #
      # Every key is present because #initialize deep-merges DEFAULT, so fetch
      # without a fallback is the right strictness — a missing section is a bug
      # in the merge, not a case to paper over.
      DEFAULT.each_key { |section| define_method(section) { @data.fetch(section) } }

      # The working set is a competition, not a queue. It used to keep the twelve
      # most recent entries, so a burst of routine events evicted the surprising
      # one that arrived before them — the opposite of what a salience score is
      # for. Sorting by salience is what makes the bound mean "the twelve that
      # matter most" rather than "the twelve that happened last".
      def remember_workspace(item)
        entries = ([item] + workspace).uniq { |entry| entry["key"] }
        @data["workspace"] = entries.sort_by { |entry| -entry["salience"].to_f }.first(MAX_WORKSPACE)
      end

      def think(text, kind: "reflection")
        entry = { "text" => text.to_s, "kind" => kind.to_s, "at" => Time.now.to_i }
        @data["thoughts"] = ([entry] + thoughts).first(MAX_THOUGHTS)
      end

      def tick!
        @data["ticks"] = ticks.to_i + 1
        @data["last_tick_at"] = Time.now.to_i
      end
    end
  end
end
