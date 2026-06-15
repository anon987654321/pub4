# frozen_string_literal: true

module Shared
  class SearchSuggestions
    OPENROUTER_BASE = "https://openrouter.ai/api/v1"
    MODEL = "google/gemini-2.0-flash-001"

    def self.for(query, vertical: nil)
      new(query, vertical: vertical).call
    end

    def initialize(query, vertical: nil)
      @query = query.to_s.strip
      @vertical = vertical
    end

    def call
      return [] if query.empty?

      llm_suggestions.presence || related_terms_fallback
    rescue StandardError => e
      Rails.logger.debug("search suggestions skipped: #{e.class}: #{e.message}")
      related_terms_fallback
    end

    private

    attr_reader :query, :vertical

    def related_terms_fallback
      tokens = query.downcase.split(/\s+/).grep(/\A[\p{L}\p{N}]{2,}\z/u)
      return [] if tokens.empty?

      suggestions = []
      suggestions << tokens.first(2).join(" ") if tokens.size > 1
      tokens.each { |token| suggestions << token[0, token.length - 1] if token.length > 3 }
      suggestions << tokens.first
      suggestions.map(&:strip).reject(&:blank?).uniq.first(5)
    end

    def llm_suggestions
      client = build_client
      return [] unless client

      prompt = <<~PROMPT
        A user searched "#{query}" in the #{vertical || "app"} vertical and got zero results.
        Suggest up to 5 related search terms they might try instead.
        Reply with JSON only: {"suggestions":["term1","term2"]}
      PROMPT

      response = client.chat(
        parameters: {
          model: MODEL,
          messages: [{ role: "user", content: prompt }],
          response_format: { type: "json_object" },
        }
      )
      content = response.dig("choices", 0, "message", "content")
      return [] if content.blank?

      Array(JSON.parse(content)["suggestions"]).map(&:to_s).map(&:strip).reject(&:blank?).first(5)
    rescue JSON::ParserError
      []
    end

    def build_client
      token = ENV["OPENROUTER_API_KEY"].to_s.strip
      return nil if token.empty?

      OpenAI::Client.new(access_token: token, uri_base: OPENROUTER_BASE)
    end
  end
end