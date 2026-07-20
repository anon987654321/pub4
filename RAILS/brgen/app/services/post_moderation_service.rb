# frozen_string_literal: true

class PostModerationService
  MODEL = ENV.fetch("MODERATION_MODEL", "groq/llama-3.1-8b-instant")
  TIMEOUT = 2

  def initialize(post)
    @post = post
  end

  def approve?
    Timeout.timeout(TIMEOUT) { moderate_sync }
  rescue Timeout::Error, StandardError => error
    Rails.logger.warn("PostModerationService timeout/error: #{error.class}: #{error.message}")
    true
  end

  private

  def moderate_sync
    prompt = <<~PROMPT
      Moderate this hyperlocal social post. Reply with exactly one word: APPROVE or REJECT.
      Reject only clear spam, hate speech, or illegal content.
      Title: #{@post.title}
      Body: #{@post.content.to_s.truncate(2000)}
    PROMPT

    verdict = RubyLLM.chat(model: MODEL).ask(prompt).content.to_s.strip.upcase
    !verdict.include?("REJECT")
  end
end
