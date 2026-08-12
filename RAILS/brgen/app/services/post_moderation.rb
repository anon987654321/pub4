# frozen_string_literal: true

# Two layers, because the one that was here had never rejected anything.
#
# `approve?` called an LLM and rescued StandardError by returning true. On
# production there is no API key — /etc/brgen.env holds SECRET_KEY_BASE and
# nothing else — so RubyLLM raised on every call, the rescue swallowed it, and
# every post was approved. 57 bot posts arrived between 2026-07-17 and 08-06 and
# passed through this class one at a time. The only trace was a Rails.logger.warn
# in a log nobody reads, and there was not even that: production.log has no
# PostModeration line at all.
#
# Fail-open is right for the LLM and wrong as the whole policy. An LLM outage
# must not stop a city forum from accepting posts. But "we could not check" is
# not the same as "this is fine", and the cheap deterministic check below needs
# no network, no key and no phrasebook — it is the signature all 57 shared.
class PostModeration
  MODEL = ENV.fetch("MODERATION_MODEL", "groq/llama-3.1-8b-instant")
  TIMEOUT = 2

  # A link, however written. Bare hostnames included: several of the 57 posted
  # "Hello http://cardff.uk," and several more wrote the domain without a scheme.
  LINK = %r{
    https?://
    | <a\s+href
    | \bwww\.[a-z0-9-]+\.[a-z]{2,}
    | \b[a-z0-9-]+\.(?:com|net|org|ru|cn|info|biz|top|xyz|shop|online|site)\b
  }ix

  # Carriage returns. A person typing in the compose box sends \n; a script
  # posting a canned message sends \r\n. Weak on its own, which is why it is
  # worth two points rather than a rejection.
  CRLF = /\r/

  # A short list, and a signal rather than a rule — the moment this becomes the
  # whole test, the bot changes a word. It is here because "SEO" and "proxy" in a
  # post from an account with no verified email are not what a neighbour writes.
  PITCH = /\b(seo|backlink|proxies|proxy offer|google 1st page|rank(?:ing)? your|guest post)\b/i

  # Reject at 3. A link alone reaches it; nothing else does on its own.
  THRESHOLD = 3

  Result = Data.define(:approved, :reason, :score)

  def initialize(post)
    @post = post
  end

  def approve? = decide.approved

  # The reason exists so the controller can tell the author what to change
  # instead of showing the same opaque refusal for every rejection.
  def decide
    score = spam_score
    return Result.new(false, :unverified_author_spam_signals, score) if score >= THRESHOLD

    Result.new(llm_approves?, :llm, score)
  end

  private

  # Weighted signals rather than one rule, because no single deterministic test
  # separates all 57 spam posts from every real one.
  #
  # Authorship gates the whole thing: every one of the 57 came from a
  # guest_*@guest.local account and every legitimate post from a named one. But
  # guests posting anonymously is a feature here, so being a guest is the
  # precondition, not the verdict.
  #
  # What this does NOT catch, stated because a filter whose gaps are undocumented
  # gets trusted past its evidence: the "I wanted to know your price" family —
  # one short sentence, no link, no CRLF, posted in Hungarian or Basque or
  # Georgian. Seventeen languages of it came through in three weeks. Catching
  # those needs language detection against the city's own language, which is a
  # bigger thing than this class, and they carry no payload — no link, no pitch,
  # nothing to click. They are noise; the ones with a URL in them are the harm.
  def spam_score
    return 0 unless unverified?

    text = "#{@post.title}\n#{@post.content}"
    score = 0
    score += 3 if LINK.match?(text)
    score += 2 if CRLF.match?(text)
    score += 2 if PITCH.match?(text)
    score
  end

  def unverified?
    user = @post.user
    return true if user.nil?

    user.guest? || (user.respond_to?(:email_verified_at) && user.email_verified_at.nil?)
  end

  # Skipped rather than attempted when there is no key. Raising once per post and
  # rescuing it is how this failed silently for three weeks; not calling out is
  # honest about the same fact and leaves a log line that means something.
  def llm_approves?
    unless configured?
      Rails.logger.info("PostModeration: no MODERATION_API_KEY, heuristics only")
      return true
    end

    Timeout.timeout(TIMEOUT) { moderate_sync }
  rescue Timeout::Error, StandardError => error
    Rails.logger.warn("PostModeration timeout/error: #{error.class}: #{error.message}")
    true
  end

  def configured?
    ENV["MODERATION_API_KEY"].present? || ENV["GROQ_API_KEY"].present? ||
      ENV["OPENAI_API_KEY"].present? || ENV["ANTHROPIC_API_KEY"].present?
  end

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
