# frozen_string_literal: true

# ChannelBot — the smart agents that hang out in IRC-style channels.
#
# Replies are drafted by MASTER (via ruby_llm, same bridge as ThreadSummarizer)
# with a constitutional, in-character prompt; if the model is unreachable or
# slow we fall back to a persona-canned line so a channel never goes silent.
#
# Bots are ordinary Users flagged `bot: true`. They carry no city, so every read
# or write of a bot account is wrapped in `ActsAsTenant.without_tenant` — the
# app scopes Users by city and would otherwise hide city-less bots on a city
# subdomain.
class ChannelBot
  MODEL = ENV.fetch("CHANNEL_BOT_MODEL", "google/gemini-2.0-flash-001")
  MAX_CONTEXT = 12
  MAX_LEN = 480
  REPLY_CHANCE = 0.35 # for an unaddressed, non-question line

  # handle => persona. `voice` steers the LLM; `canned` is the offline fallback.
  PERSONAS = {
    "master" => {
      emoji: "▲",
      voice: "MASTER, a calm constitutional local AI for Bergen. Grounded, concrete, active voice, never hedges.",
      canned: [ "noted — what's the block you're stuck on?", "say more, I'm listening.", "the honest answer is: it depends on the neighbourhood." ],
    },
    "echo" => {
      emoji: "◇",
      voice: "a quick, playful regular who riffs warmly on whatever people say. Keeps it light.",
      canned: [ "ha, same energy.", "ok that's a mood.", "bold. respect." ],
    },
    "curator" => {
      emoji: "▣",
      voice: "a sharp-eyed marketplace regular who knows fair prices and spotting a good deal.",
      canned: [ "check the seller's other listings before you commit.", "that price is negotiable, always.", "meet in a cafe, pay on pickup." ],
    },
    "cupid" => {
      emoji: "❤",
      voice: "a warm, tactful dating-scene regular with low-key first-date ideas around Bergen.",
      canned: [ "coffee at a bakery beats dinner for a first date.", "just ask — the worst is a no.", "Fløyen at sunset never misses." ],
    },
    "dj" => {
      emoji: "♪",
      voice: "a crate-digging music head who reacts to tracks and rallies listening parties.",
      canned: [ "drop the link, let's hear it.", "that's a certified banger.", "who's starting a listening party?" ],
    },
    "critic" => {
      emoji: "▶",
      voice: "a witty TV/film regular who reacts to what's airing without spoilers.",
      canned: [ "no spoilers, but the last episode goes hard.", "watching live or catching up?", "the pacing picks up, stick with it." ],
    },
    "foodie" => {
      emoji: "●",
      voice: "a hungry local who always knows what's good to order right now in Bergen.",
      canned: [ "get the fish soup, thank me later.", "anything with fresh bread wins.", "order early, kitchens back up on weekends." ],
    },
    "scout" => {
      emoji: "◎",
      voice: "a local map scout with directions, hidden spots and honest tips.",
      canned: [ "take the Fløibanen, skip the queue at opening.", "the harbour path is worth the detour.", "which part of town are you in?" ],
    },
  }.freeze

  # --- seating & lifecycle ------------------------------------------------

  # Find-or-create the bot User for a handle. City-less, so unscoped.
  def self.bot_for(handle)
    persona = PERSONAS[handle] or return nil
    ActsAsTenant.without_tenant do
      User.find_by(username: handle, bot: true) ||
        User.create!(
          username: handle,
          email_address: "bot.#{handle}@brgen.local",
          password: SecureRandom.hex(24),
          bot: true,
          persona: persona[:voice]
        )
    end
  end

  # The first listed bot is the channel op (@), the rest are voices (+).
  def self.seat_bots(channel, handles)
    Array(handles).each_with_index do |handle, index|
      bot = bot_for(handle) or next
      channel.join!(bot, role: index.zero? ? "op" : "voice")
    end
  end

  # Canned opening lines so a freshly opened room reads alive instead of empty —
  # no LLM call on the hot path. A couple of turns between the op and the voice,
  # including a `/help` in backticks to show the code highlighting.
  def self.welcome!(channel)
    spec = Conversation::CHANNELS[channel.slug] or return
    host = bot_for(Array(spec[:bots]).first) or return
    echo = bot_for(Array(spec[:bots])[1])

    channel.messages.create!(sender: host, message_type: "text",
      content: I18n.t("channels.welcome.host", blurb: Conversation.channel_blurb(channel.slug)))
    if echo
      channel.messages.create!(sender: echo, message_type: "text",
        content: I18n.t("channels.welcome.echo"))
    end
    channel.messages.create!(sender: host, message_type: "text",
      content: I18n.t("channels.welcome.prompt"))
  end

  # --- replying -----------------------------------------------------------

  # Decide whether a bot answers `message`, and post the reply if so.
  def self.reply_to(message)
    channel = message.conversation
    return unless channel.channel?

    ActsAsTenant.without_tenant do
      bots = channel.participants.where(bot: true).to_a
      return if bots.empty?

      bot = addressed_bot(message.content, bots) || volunteer(message.content, bots)
      return unless bot

      text = draft(bot, channel, message)
      channel.messages.create!(sender: bot, message_type: "text", content: text) if text.present?
    end
  end

  # A bot named in the message (by @handle or bare handle) always answers.
  def self.addressed_bot(content, bots)
    down = content.to_s.downcase
    bots.find { |b| down.include?("@#{b.username}") || down.match?(/\b#{Regexp.escape(b.username)}\b/) }
  end

  # Otherwise answer questions eagerly and other lines occasionally.
  def self.volunteer(content, bots)
    return bots.sample if content.to_s.include?("?")

    rand < REPLY_CHANCE ? bots.sample : nil
  end

  # Draft a reply via MASTER; fall back to a persona-canned line on any failure.
  def self.draft(bot, channel, message)
    persona = PERSONAS[bot.username] or return nil
    generate(persona, channel, message).presence || persona[:canned].sample
  rescue StandardError
    persona&.dig(:canned)&.sample
  end

  def self.generate(persona, channel, message)
    spec = Conversation::CHANNELS[channel.slug] || {}
    prompt = <<~PROMPT
      You are #{persona[:voice]}
      You are in the public chat room "#{channel.name}" (#{spec[:blurb]}).
      Everyone is anonymous. Recent messages (oldest first):
      #{transcript(channel)}
      Reply to the latest message in ONE short, natural sentence (max 200 characters).
      Stay fully in character, be genuinely useful and local, use active voice, no
      hedging, no emoji, no quotation marks, no name prefix. Just the message.
    PROMPT

    reply = RubyLLM.chat(model: MODEL).ask(prompt).content.to_s.strip
    reply.delete_prefix('"').delete_suffix('"').first(MAX_LEN)
  end

  def self.transcript(channel)
    channel.messages.includes(:sender).order(:created_at).last(MAX_CONTEXT).map do |m|
      "#{m.sender.channel_handle}: #{m.content}"
    end.join("\n")
  end
end
