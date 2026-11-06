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
  # One unprompted reply per room per window: every '?' line volunteers a bot
  # and an LLM call, so without it one person could make the bots flood a room.
  VOLUNTEER_COOLDOWN = 30.seconds

  # handle => persona. `voice` steers the LLM. The offline fallback lines live in
  # channels.bots.<handle> per locale, so a Norwegian room is answered in Norwegian
  # even when the model is unreachable.
  PERSONAS = {
    "master" => {
      emoji: "▲",
      voice: "MASTER, a calm constitutional local AI. Grounded, concrete, active voice, never hedges."
    },
    "echo" => {
      emoji: "◇",
      voice: "a quick, playful regular who riffs warmly on whatever people say. Keeps it light."
    },
    "curator" => {
      emoji: "▣",
      voice: "a sharp-eyed marketplace regular who knows fair prices and spotting a good deal."
    },
    "cupid" => {
      emoji: "❤",
      voice: "a warm, tactful dating-scene regular with low-key first-date ideas."
    },
    "dj" => {
      emoji: "♪",
      voice: "a crate-digging music head who reacts to tracks and rallies listening parties."
    },
    "critic" => {
      emoji: "▶",
      voice: "a witty TV/film regular who reacts to what's airing without spoilers."
    },
    "foodie" => {
      emoji: "●",
      voice: "a hungry local who knows how to find a good meal in the city."
    },
    "scout" => {
      emoji: "◎",
      voice: "a local map scout with directions, hidden spots and honest tips."
    }
  }.freeze

  # --- seating & lifecycle ------------------------------------------------

  # Find-or-create the bot User for a handle. City-less, so unscoped.
  def self.bot_for(handle)
    persona = PERSONAS[handle] or return nil
    ActsAsTenant.without_tenant do
      bot = User.find_by(username: handle, bot: true)
      if bot
        bot.update_column(:persona, persona[:voice]) if bot.persona != persona[:voice]
        bot
      else
        User.create!(
          username: handle,
          email_address: "bot.#{handle}@brgen.local",
          password: SecureRandom.hex(24),
          bot: true,
          persona: persona[:voice]
        )
      end
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

    # In the room's language, not the request's or the job's: a room is opened
    # from whichever page or job reaches it first.
    I18n.with_locale(room_locale(channel)) do
      channel.messages.create!(sender: host, message_type: "text",
        content: I18n.t("channels.welcome.host", blurb: Conversation.channel_blurb(channel.slug)))
      if echo
        channel.messages.create!(sender: echo, message_type: "text",
          content: I18n.t("channels.welcome.echo"))
      end
      channel.messages.create!(sender: host, message_type: "text",
        content: I18n.t("channels.welcome.prompt"))
    end
  end

  # --- replying -----------------------------------------------------------

  # Decide whether a bot answers `message`, and post the reply if so.
  def self.reply_to(message)
    channel = message.conversation
    return if message.sender.bot?

    ActsAsTenant.without_tenant do
      bots = channel.participants.where(bot: true).to_a
      return if bots.empty?

      bot = bot_for_message(channel, message, bots)
      return unless bot

      text = draft(bot, channel, message)
      channel.messages.create!(sender: bot, message_type: "text", content: text) if text.present?
    end
  end

  def self.bot_for_message(channel, message, bots)
    master = bots.find { |bot| bot.username == "master" }
    return master if master && channel.conversation_type == "direct"
    return master if master && channel.group_dm? && addressed_bot(message.content, [ master ])

    addressed_bot(message.content, bots) || volunteer(channel, message.content, bots) if channel.channel?
  end

  # A bot named in the message (by @handle or bare handle) always answers.
  def self.addressed_bot(content, bots)
    down = content.to_s.downcase
    bots.find { |b| down.include?("@#{b.username}") || down.match?(/\b#{Regexp.escape(b.username)}\b/) }
  end

  # Otherwise answer questions eagerly and other lines occasionally, at most
  # once per VOLUNTEER_COOLDOWN in a room.
  def self.volunteer(channel, content, bots)
    key = "channel_bot:volunteered:#{channel.id}"
    return if Rails.cache.exist?(key)
    return unless content.to_s.include?("?") || rand < REPLY_CHANCE

    Rails.cache.write(key, true, expires_in: VOLUNTEER_COOLDOWN)
    bots.sample
  end

  # Draft a reply via MASTER; fall back to a persona-canned line on any failure.
  def self.draft(bot, channel, message)
    persona = PERSONAS[bot.username] or return nil
    generate(persona, channel, message).presence || canned_line(bot.username, channel)
  rescue StandardError
    persona && canned_line(bot.username, channel)
  end

  # The language a room is spoken in: its city's, as the site resolves it for
  # a visitor (brgen.no is nb). A room with no city takes the app default.
  def self.room_locale(channel)
    city_locale = channel.city&.locale
    city_locale.present? ? Brgen::LocaleBridge.resolve(city_locale) : I18n.default_locale
  end

  LANGUAGE_NAMES = { nb: "Norwegian Bokmål", en: "English" }.freeze

  def self.language_name(channel) = LANGUAGE_NAMES.fetch(room_locale(channel).to_sym, "English")

  def self.canned_lines(handle, locale)
    Array(I18n.t("channels.bots.#{handle}", locale:, default: []))
  end

  def self.canned_line(handle, channel) = canned_lines(handle, room_locale(channel)).sample

  def self.generate(persona, channel, message)
    return generate_master(channel, message) if persona.equal?(PERSONAS["master"])

    prompt = prompt_for(persona, channel)
    reply = Shared::Llm.new(model: MODEL).ask(prompt, json: false).to_s.strip
    reply.delete_prefix('"').delete_suffix('"').first(MAX_LEN)
  end

  def self.city_name_for(channel)
    channel.city&.name.presence
  end

  # One prompt builder keeps city context explicit and testable without making
  # a background job depend on request-scoped Current attributes.
  def self.prompt_for(persona, channel)
    city = city_name_for(channel)
    location = city.present? ? city : "the city"
    blurb = Conversation.channel_blurb(channel.slug)
    <<~PROMPT
      You are #{persona[:voice]}
      You are in the public chat room "#{channel.name}" in #{location} (#{blurb}).
      Use the room's city as your local context. Never assume another city or
      invent specific venues, events or opening hours. When unsure, ask for a
      neighbourhood or a little more context.
      Everyone is anonymous. Recent messages (oldest first):
      #{transcript(channel)}
      Reply to the latest message in ONE short, natural sentence (max 200 characters).
      Stay fully in character, be genuinely useful and local, use active voice, no
      hedging, no emoji, no quotation marks, no name prefix. Just the message.
      Write the reply in #{language_name(channel)}, the language of this room.
    PROMPT
  end

  def self.master_context_for(channel)
    city = city_name_for(channel)
    language = "Reply in #{language_name(channel)}, the language of this room."
    return language if city.blank?

    "This public room is city-scoped to #{city}. Use that city for local context; " \
      "do not assume another city or invent venue names, events or opening hours. #{language}"
  end

  def self.generate_master(channel, message)
    messages = context_messages(channel)
    Shared::MasterMessenger.new.reply(
      messages:, sender: message.sender, message:,
      session_key: "brgen:conversation:#{channel.id}", channel: "brgen-messenger",
      context: master_context_for(channel)
    ).to_s.first(MAX_LEN)
  end

  # Only what the room can still read: an unsent or expired line never goes back
  # into a prompt.
  def self.context_messages(channel)
    readable = channel.messages.visible
    readable = readable.unexpired.includes(:sender)
    readable.order(:created_at).last(MAX_CONTEXT)
  end

  def self.transcript(channel)
    context_messages(channel).map do |m|
      "#{m.sender.channel_handle}: #{m.content}"
    end.join("\n")
  end
end
