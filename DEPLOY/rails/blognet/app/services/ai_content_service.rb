# frozen_string_literal: true

class AiContentService
  MODEL = ENV.fetch("BLOGNET_AI_MODEL", "google/gemini-2.0-flash-001")

  def initialize(post)
    @post = post
  end

  def generate
    prompt = <<~PROMPT
      You are a professional blog writer for blognet.no.
      Write a clear, engaging article body for the title below.
      Use short paragraphs, concrete detail, and an approachable tone.
      Do not repeat the title. No markdown headings.
      Title: #{@post.title}
    PROMPT

    chat = RubyLLM.chat(model: MODEL)
    chat.ask(prompt).content.to_s.strip
  rescue StandardError => error
    Rails.logger.error("AiContentService failed: #{error.message}")
    "Failed to generate content."
  end
end