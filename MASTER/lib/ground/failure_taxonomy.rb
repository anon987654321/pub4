# frozen_string_literal: true

module Master
  module Ground
    # rules.yml failure_taxonomy — classify errors and return retry strategy.
    class FailureTaxonomy
      DEFAULTS = {
        "transient" => { "strategy" => "exponential_backoff", "max_retries" => 3 },
        "permanent" => { "strategy" => "fail_fast", "max_retries" => 0 },
        "ambiguous" => { "strategy" => "human_intervention", "max_retries" => 0, "checkpoint_before" => true },
      }.freeze

      def initialize(rules_data: nil)
        raw = (rules_data || Master.load_yaml(Master::RULES_PATH).fetch("failure_taxonomy", {}))
        @categories = raw.transform_keys(&:to_s)
        @patterns = build_patterns
      end

      def classify(message)
        text = message.to_s
        @patterns.each do |category, regex|
          return category.to_sym if regex.match?(text)
        end
        :ambiguous
      end

      def strategy_for(category)
        key = category.to_s
        entry = @categories[key] || {}
        DEFAULTS.fetch(key, DEFAULTS["ambiguous"]).merge(entry.slice("strategy", "max_retries", "checkpoint_before"))
      end

      def handle(error)
        category = classify(error.message)
        { category:, **strategy_for(category).transform_keys(&:to_sym) }
      end

      def retry?(error, attempt:)
        info = handle(error)
        attempt < info[:max_retries].to_i
      end

      def backoff_seconds(attempt) = self.class.backoff_seconds(attempt)

      # Class-level so callers that want only the capped exponential formula
      # (e.g. Io::ReplicateClient's HTTP retry loop) don't need to instantiate
      # a full FailureTaxonomy (which loads rules.yml) for this.
      def self.backoff_seconds(attempt)
        [2**attempt, 60].min
      end

      private

      def build_patterns
        {
          "transient" => build_category_re("transient", Master::Fix::Constants::TRANSIENT_RE),
          "permanent" => build_category_re("permanent", Master::Fix::Constants::PERMANENT_RE),
          "ambiguous" => build_category_re("ambiguous", Master::Fix::Constants::AMBIGUOUS_RE),
        }
      end

      def build_category_re(category, fallback)
        examples = Array(@categories.dig(category, "examples"))
        return fallback if examples.empty?

        parts = examples.map do |ex|
          ex.to_s.split("_").map { |part| Regexp.escape(part) }.join("[ ._-]?")
        end
        Regexp.new(parts.join("|"), Regexp::IGNORECASE)
      rescue StandardError
        fallback
      end
    end
  end
end
