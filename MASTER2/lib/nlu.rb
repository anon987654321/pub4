# frozen_string_literal: true

require "json"

module NLU
  class Classifier
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_MAX_TOKENS = 500
    DEFAULT_TOP_P = 1.0
    DEFAULT_MIN_CONFIDENCE = 0.55
    DEFAULT_MAX_KEYWORDS = 12

    ITEMS_SCHEMA_FRAGMENT = { items: { type: "string" } }.freeze

    def initialize(llm_client:, logger: nil, model: nil, min_confidence: DEFAULT_MIN_CONFIDENCE)
      @llm_client = llm_client
      @logger = logger
      @model = model
      @min_confidence = min_confidence
    end

    def classify_signals(signals:, available_intents:, user_locale: "en", options: {})
      return fallback_classify_signals(signals: signals, available_intents: available_intents) if signals.to_s.strip.empty?
      return fallback_classify_signals(signals: signals, available_intents: available_intents) if available_intents.nil? || available_intents.empty?

      prompt = build_classification_prompt(
        signals: signals,
        available_intents: available_intents,
        user_locale: user_locale
      )

      raw_response = request_llm_completion(prompt: prompt, options: options)
      classification = parse_classification_json(raw_response)

      return fallback_classify_signals(signals: signals, available_intents: available_intents) if classification.nil?
      return fallback_classify_signals(signals: signals, available_intents: available_intents) unless valid_intent?(classification, available_intents)

      classification
    end

    def fallback_classify_signals(signals:, available_intents:)
      intent_keywords = extract_intent_keywords(available_intents)
      signal_text = signals.to_s.downcase

      best_intent = intent_keywords
        .map { |intent_name, keywords| [intent_name, keyword_score(signal_text, keywords)] }
        .max_by { |_intent_name, score| score }

      return default_unknown_classification if best_intent.nil?

      intent_name, score = best_intent
      confidence = score_to_confidence(score, intent_keywords.fetch(intent_name, []).length)

      return default_unknown_classification if confidence < @min_confidence

      { "intent" => intent_name, "confidence" => confidence, "keywords" => intent_keywords.fetch(intent_name, []) }
    end

    def extract_intent_keywords(available_intents, max_keywords: DEFAULT_MAX_KEYWORDS)
      intents_array = normalize_intents(available_intents)
      intents_array.each_with_object({}) do |intent_entry, keyword_map|
        intent_name = intent_entry.fetch("name")
        source_phrases = Array(intent_entry.fetch("examples", [])) + Array(intent_entry.fetch("keywords", []))
        keywords = source_phrases.flat_map { |phrase| phrase.to_s.downcase.scan(/[a-z0-9]+/) }
        keyword_map[intent_name] = keywords.uniq.first(max_keywords)
      end
    end

    def build_classification_prompt(signals:, available_intents:, user_locale: "en")
      intents_array = normalize_intents(available_intents)
      intents_block = intents_array.map { |intent| format_intent_for_prompt(intent) }.join("\n")

      <<~PROMPT
        You are an NLU classifier. Output ONLY valid JSON matching this schema:
        #{JSON.pretty_generate(intent_schema(intents_array.map { |intent| intent.fetch("name") }))}

        Locale: #{user_locale}

        Available intents:
        #{intents_block}

        Signals to classify:
        #{signals}

        Rules:
        - Choose the best matching intent from "intent".
        - Provide a confidence from 0.0 to 1.0.
        - Provide up to 12 matched keywords from the user signals.
      PROMPT
    end

    def intent_schema(intent_names)
      {
        type: "object",
        additionalProperties: false,
        required: %w[intent confidence keywords],
        properties: {
          intent: { type: "string", enum: intent_names },
          confidence: { type: "number", minimum: 0.0, maximum: 1.0 },
          keywords: { type: "array" }.merge(ITEMS_SCHEMA_FRAGMENT)
        }
      }
    end

    private

    def request_llm_completion(prompt:, options:)
      request_params = {
        model: @model,
        temperature: options.fetch(:temperature, DEFAULT_TEMPERATURE),
        max_tokens: options.fetch(:max_tokens, DEFAULT_MAX_TOKENS),
        top_p: options.fetch(:top_p, DEFAULT_TOP_P),
        prompt: prompt
      }.compact

      @llm_client.complete(**request_params)
    rescue StandardError => error
      @logger&.warn("NLU LLM request failed: #{error.class}: #{error.message}")
      nil
    end

    def parse_classification_json(raw_response)
      return nil if raw_response.nil?

      json_text = extract_json_text(raw_response)
      JSON.parse(json_text)
    rescue JSON::ParserError => error
      @logger&.warn("NLU JSON parse failed: #{error.message}")
      nil
    end

    def extract_json_text(raw_response)
      raw_response.to_s.strip
    end

    def normalize_intents(available_intents)
      case available_intents
      when Array
        available_intents.map { |entry| normalize_intent_entry(entry) }
      when Hash
        available_intents.fetch("intents", available_intents.fetch(:intents, []))
          .map { |entry| normalize_intent_entry(entry) }
      else
        []
      end
    end

    def normalize_intent_entry(entry)
      return entry if entry.is_a?(Hash) && entry.key?("name")

      if entry.is_a?(Hash)
        {
          "name" => entry.fetch(:name, entry.fetch("name", "")).to_s,
          "description" => entry.fetch(:description, entry.fetch("description", "")).to_s,
          "examples" => entry.fetch(:examples, entry.fetch("examples", [])),
          "keywords" => entry.fetch(:keywords, entry.fetch("keywords", []))
        }
      else
        { "name" => entry.to_s, "description" => "", "examples" => [], "keywords" => [] }
      end
    end

    def format_intent_for_prompt(intent_entry)
      intent_name = intent_entry.fetch("name").to_s
      description = intent_entry.fetch("description", "").to_s
      examples = Array(intent_entry.fetch("examples", [])).first(5)

      lines = []
      lines << "- #{intent_name}"
      lines << "  description: #{description}" unless description.empty?
      lines << "  examples: #{examples.join(" | ")}" unless examples.empty?
      lines.join("\n")
    end

    def valid_intent?(classification, available_intents)
      return false unless classification.is_a?(Hash)

      intent_name = classification.fetch("intent", nil)
      confidence = classification.fetch("confidence", nil)
      return false if intent_name.to_s.empty?
      return false unless confidence.is_a?(Numeric)

      allowed_names = normalize_intents(available_intents).map { |intent| intent.fetch("name") }
      allowed_names.include?(intent_name) && confidence >= @min_confidence
    end

    def keyword_score(signal_text, keywords)
      return 0 if signal_text.empty? || keywords.empty?

      keywords.count { |keyword| signal_text.include?(keyword) }
    end

    def score_to_confidence(score, keyword_count)
      return 0.0 if score <= 0 || keyword_count <= 0

      ratio = score.to_f / keyword_count.to_f
      [[ratio, 1.0].min, 0.0].max
    end

    def default_unknown_classification
      { "intent" => "unknown", "confidence" => 0.0, "keywords" => [] }
    end
  end
end