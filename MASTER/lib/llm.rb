# frozen_string_literal: true
require "net/http"
require "json"
require "uri"

module Master
  class LLM
    TIERS = {
      fast:   "google/gemini-2.0-flash-001",
      code:   "x-ai/grok-3-mini-beta",
      medium: "anthropic/claude-sonnet-4",
      strong: "anthropic/claude-opus-4"
    }.freeze

    def initialize
      @api_key = ENV["OPENROUTER_API_KEY"]
      @base_uri = URI("https://openrouter.ai/api/v1/chat/completions")
    end

    def ask(prompt, tier: :fast, max_tokens: 2048)
      return Result.err("No API key") unless @api_key
      model = TIERS[tier] || TIERS[:fast]
      body = {
        model: model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: max_tokens
      }
      http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      req = Net::HTTP::Post.new(@base_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json
      resp = http.request(req)
      data = JSON.parse(resp.body)
      if data["choices"]&.first
        Result.ok(data["choices"].first.dig("message", "content"))
      else
        Result.err(data["error"]&.dig("message") || "Unknown error")
      end
    rescue => e
      Result.err(e.message)
    end
  end
end
