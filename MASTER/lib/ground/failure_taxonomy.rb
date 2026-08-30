# frozen_string_literal: true

module Master
  module Ground
    # rules.yml failure_taxonomy — classify errors and return retry strategy.
    class FailureTaxonomy
      DEFAULTS = {
        # A paid provider spend limit. Distinct from transient because an
        # in-place retry cannot succeed, and distinct from permanent because
        # the condition lifts on its own — a window rolls, a balance refills.
        # The strategy is to pause the paid lane and re-probe on backoff, which
        # Ground::QuotaGate owns; max_retries stays 0 so nothing retries in
        # place while it waits.
        "exhausted" => { "strategy" => "pause_and_reprobe", "max_retries" => 0 },
        "transient" => { "strategy" => "exponential_backoff", "max_retries" => 3 },
        "permanent" => { "strategy" => "fail_fast", "max_retries" => 0 },
        "ambiguous" => { "strategy" => "human_intervention", "max_retries" => 0, "checkpoint_before" => true },
      }.freeze
      SHARED_LOCK = Mutex.new

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

      # One classifier for the whole process. Ground::QuotaGate asks the same
      # yes/no question once per failed provider call — hundreds of times in a
      # council run — against the same rules.yml, so it reuses this taxonomy
      # rather than carrying a second copy of the patterns.
      def self.shared = SHARED_LOCK.synchronize { @shared ||= new }

      def self.exhausted?(message) = shared.classify(message) == :exhausted

      private

      # Exhaustion is matched first: an "insufficient credits" notice that also
      # carries a 429 is an empty account, not a throttle, and reading it as
      # transient is what makes a run spend N calls learning one fact.
      #
      # It alone keeps its pattern in code rather than in rules.yml examples.
      # build_category_re only reaches a fallback when a category declares no
      # examples, and the examples grammar (word_word -> word[ ._-]?word) cannot
      # express \b402\b — the HTTP status that carries this failure with no
      # prose at all. rules.yml still owns the exhausted *policy*; the code owns
      # the pattern.
      def build_patterns
        {
          "exhausted" => build_category_re("exhausted", Master::Fix::Constants::EXHAUSTED_RE),
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
