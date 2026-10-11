# frozen_string_literal: true

module Master
  module Cognition
    # Durable internal state: a computational self-model, not evidence that
    # MASTER is phenomenally conscious. Proxy metrics stay explicitly labelled.
    class State
      DEFAULT = {
        "identity" => { "name" => "MASTER", "continuity" => 1.0, "agency" => 0.5, "coherence" => 1.0 },
        "affect" => { "valence" => 0.0, "arousal" => 0.25, "novelty" => 0.0, "uncertainty" => 0.5 },
        "drives" => { "safety" => 1.0, "coherence" => 0.8, "curiosity" => 0.6, "agency" => 0.5, "affiliation" => 0.4 },
        "workspace" => [],
        "predictions" => { "transitions" => {}, "previous_event" => nil, "last_error" => 0.0 },
        "outcomes" => { "records" => {} },
        "self_model" => {},
        "thoughts" => [],
        "metrics" => { "integration" => 0.0, "prediction_error" => 0.0, "continuity" => 1.0, "attention" => 0.0 },
        "last_tick_at" => 0,
        "ticks" => 0,
      }.freeze

      MAX_WORKSPACE = 12
      MAX_THOUGHTS = 20

      class << self
        def load(path)
          return new({}) unless File.file?(path)

          raw = Master.load_yaml(path)
          valid = valid_checkpoint?(raw)
          new(valid ? raw : {}, checkpoint_valid: valid)
        rescue StandardError
          new({})
        end

        def valid_checkpoint?(raw)
          return false unless raw.is_a?(Hash)
          return false unless raw["ticks"].is_a?(Numeric)
          return false unless raw["identity"].is_a?(Hash) && raw["predictions"].is_a?(Hash)
          return false if raw.key?("workspace") && !raw["workspace"].is_a?(Array)
          return false if raw.key?("self_model") && !raw["self_model"].is_a?(Hash)
          return false if raw.key?("metrics") && !raw["metrics"].is_a?(Hash)
          if raw.key?("outcomes")
            outcomes = raw["outcomes"]
            return false unless outcomes.is_a?(Hash)
            records = outcomes.fetch("records", {})
            return false unless records.is_a?(Hash)
            return false unless records.all? { |_key, record|
              record.is_a?(Hash) &&
                %w[successes failures inconclusive brier_count].all? { |counter|
                  !record.key?(counter) || record[counter].is_a?(Numeric)
                } &&
                (!record.key?("observations") || record["observations"].is_a?(Array)) &&
                (!record.key?("seen_receipts") || record["seen_receipts"].is_a?(Array))
            }
          end
          if raw["self_model"].is_a?(Hash) && raw["self_model"].key?("assessments")
            assessments = raw["self_model"]["assessments"]
            return false unless assessments.is_a?(Hash) && assessments.values.all? { |row| row.is_a?(Hash) }
          end

          true
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

      attr_reader :data, :checkpoint_valid

      # DEFAULT is frozen and deep_dup'd on the way in, so a caller that passes
      # DEFAULT itself still gets a mutable state rather than a FrozenError two
      # layers down.
      def initialize(data, checkpoint_valid: false)
        @data = self.class.deep_merge(self.class.deep_dup(DEFAULT), data)
        @checkpoint_valid = checkpoint_valid == true
        unless @checkpoint_valid
          @data["metrics"]["continuity"] = 0.0
          @data["metrics"]["checkpoint_continuity"] = 0.0
          @data["identity"]["continuity"] = 0.0
        end
      end

      def mark_checkpoint_valid!
        @checkpoint_valid = true
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
