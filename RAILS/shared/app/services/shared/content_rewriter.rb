# frozen_string_literal: true

require "json"

module Shared
  # LLM rephrase pass for scraped social content — produces unique local-voice posts.
  class ContentRewriter
    MODEL = ENV.fetch("REWRITE_MODEL", ENV.fetch("SCRAPE_MODEL", "google/gemini-2.0-flash-001"))
    TIMEOUT = 20

    Result = Data.define(:title, :body, :comments)

    def self.rewrite(title:, body:, comments: [], city_name: "local community", locale: "en")
      new(city_name:, locale:).rewrite(title:, body:, comments:)
    end

    def initialize(city_name:, locale: "en")
      @city_name = city_name
      @locale = locale
    end

    def rewrite(title:, body:, comments: [])
      raw = ask_llm(title:, body:, comments:)
      Result.new(
        title: StrunkWhitePass.call(raw[:title]),
        body: StrunkWhitePass.call(raw[:body]),
        comments: Array(raw[:comments]).map { |comment|
 StrunkWhitePass.call(comment) }.reject { |comment| comment.to_s.strip.empty? },
      )
    rescue StandardError => error
      Rails.logger.warn("ContentRewriter fallback: #{error.class}: #{error.message}") if defined?(Rails)
      Result.new(
        title: StrunkWhitePass.call(title),
        body: StrunkWhitePass.call(body),
        comments: Array(comments).map { |comment|
 StrunkWhitePass.call(comment) }.reject { |comment| comment.to_s.strip.empty? },
      )
    end

    private

    def ask_llm(title:, body:, comments:)
      prompt = <<~PROMPT
        Rewrite scraped forum content as original posts for #{@city_name}, a hyperlocal social network.
        Language: #{@locale}. Keep facts; change wording so nothing traces to Reddit or other sources.
        Drop subreddit tags, scores, usernames, URLs, and meta commentary.
        Strunk & White: active voice, omit needless words, no hedging.
        Generate #{comment_target(comments)} short comments that fit the thread (no usernames in output).

        Source title: #{title}
        Source body: #{body.presence || "(empty)"}
        Source comments: #{comments.presence&.join(" | ") || "(none)"}

        Reply JSON only:
        {"title":"...","body":"...","comments":["...","..."]}
      PROMPT

      payload = Timeout.timeout(TIMEOUT) {
        RubyLLM.chat(model: MODEL).ask(prompt).content.to_s
      }
      parse_payload(payload, fallback_title: title, fallback_body: body, fallback_comments: comments)
    end

    def comment_target(comments)
      count = Array(comments).size
      count.positive? ? count : rand(2..4)
    end

    def parse_payload(payload, fallback_title:, fallback_body:, fallback_comments:)
      json = JSON.parse(payload[/\{.*\}/m] || payload)
      {
        title: json["title"].presence || fallback_title,
        body: json["body"].presence || fallback_body,
        comments: Array(json["comments"]).presence || fallback_comments,
      }
    rescue JSON::ParserError
      {
        title: fallback_title,
        body: fallback_body,
        comments: fallback_comments,
      }
    end
  end
end
