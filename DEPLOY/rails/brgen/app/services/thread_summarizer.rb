# frozen_string_literal: true

# ThreadSummarizer — AI summary of long comment threads via ruby_llm (MASTER-style constitutional prompt).
# Used for CB07: summaries on threads > LONG_THREAD_THRESHOLD replies.
# Streaming friendly: can be called with block for chunks if desired.
class ThreadSummarizer
  MODEL = ENV.fetch("SUMMARY_MODEL", "google/gemini-2.0-flash-001")

  def self.call(comment, &block)
    new(comment).call(&block)
  end

  def initialize(comment)
    @comment = comment
  end

  def call(&block)
    return nil unless @comment.long_thread?

    thread_text = build_thread_text

    prompt = <<~PROMPT
      You are MASTER, a constitutional AI for a hyperlocal Norwegian city social network (brgen).
      Summarize the following comment thread in exactly 3 short sentences.
      Use active voice, concrete details, no hedges, no "in summary".
      Focus on the main points of agreement/disagreement and key local context.
      Keep under 200 chars total.
      Thread (root + top replies):
      #{thread_text}
    PROMPT

    if block_given?
      # Streaming path (future: wire to turbo chunks via cable_ready or ws)
      response = ""
      chat = RubyLLM.chat(model: MODEL)
      chat.ask(prompt) do |chunk|
        response << chunk.content.to_s
        block.call(chunk.content.to_s) if chunk.content
      end
      persist_summary(response)
      response
    else
      chat = RubyLLM.chat(model: MODEL)
      summary = chat.ask(prompt).content.to_s.strip
      persist_summary(summary)
      summary
    end
  end

  private

  def build_thread_text
    root = @comment
    text = "ROOT: #{root.content}\n"
    root.replies.best.limit(10).each_with_index do |reply, i|
      text << "REPLY#{i+1}: #{reply.content}\n"
    end
    text[0, 4000] # truncate for token safety
  end

  def persist_summary(text)
    @comment.update!(thread_summary: text, summary_updated_at: Time.current)
  end
end
