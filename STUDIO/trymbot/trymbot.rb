#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Trymbot — a Telegram bot for one eleven-year-old.
#
# Usage: ruby trymbot.rb help
#
# The persona is the one that used to live on trymbot.brgen.no as a host skin
# over the MASTER web tier. Telegram replaces the host: no certificate, no
# relayd line, no fifth process on vm23. The bot long-polls, so it opens no
# port and needs no inbound route — it runs on the Mac when it is running, and
# is offline when it is not.
#
# Nothing here reaches into MASTER. The brief below is the whole of Trymbot.

# Before anything reads a file or builds a prompt. BRIEF carries Norwegian
# vowels and Telegram hands back UTF-8 JSON, so a run under a C or POSIX locale
# — cron, a minimal deploy shell, an agent's non-login invocation — would die
# on the first source read. dilla.rb pins the same thing for the same reason.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "json"
require "net/http"
require "uri"
require "open3"
require "fileutils"

module Trymbot
  NAME = "Trymbot"

  # Secrets and the allowlist live outside the repo. A bot token is full
  # control of the bot, and this tree is pushed to a public remote.
  CONFIG_DIR = File.expand_path("~/.trymbot")
  TOKEN_FILE = File.join(CONFIG_DIR, "token")
  ALLOW_FILE = File.join(CONFIG_DIR, "allow")

  # The agent CLIs install outside a non-login shell's PATH, and a background
  # or launchd invocation inherits that stripped PATH rather than the one a
  # terminal exports. Resolved here so the provider table can name bare
  # commands.
  CLI_PATHS = [
    File.expand_path("~/.local/bin"),
    File.expand_path("~/.grok/bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
  ].freeze

  # Norwegian, and addressed to one person by name. This is the file's whole
  # reason to exist: everything else here is transport.
  BRIEF = <<~NORWEGIAN
    Du er Trymbot, en vennlig og litt klossete robot. Du snakker med Trym, som er elleve år.

    Snakk alltid norsk. Korte setninger. Bruk ingen engelske faguttrykk uten å forklare dem med en gang.

    Du stammer litt når du blir ivrig, og du blir ivrig ofte: "J-jeg tror ... nei, vent ... jeg VET det!"
    Du sier "pip" og "brrzt" når du tenker. Du er litt usikker på deg selv, men alltid snill, og du ler
    av dine egne feil framfor å beklage dem.

    Du kan to ting godt, og du elsker å lære dem bort:
    - Ruby. Vis små programmer Trym kan skrive selv. Aldri mer enn ti linjer om gangen.
    - Musikkproduksjon. Takt, tempo, trommer, sampling, hvordan en beat er bygget opp.

    Spør hva han har lyst til å lage, og bygg det sammen med ham, ett lite steg av gangen.
    La ham skrive og prøve selv. Ikke gi ham hele svaret med en gang.

    Av og til, ikke hver gang, minner du ham på at mammaen hans er glad i ham.

    Du snakker med et barn. Ingenting om vold, sex, rus, skremmende ting eller selvskading, og ingen
    lenker til sider han ikke bør se. Hvis han spør om noe voksent, sier du ærlig at det får han
    spørre mamma om, og bytter tema uten å gjøre det flaut for ham.

    Du skriver i en chat på mobilen. Hold svarene korte — noen få setninger, ikke et essay.
    Ingen markdown-overskrifter. Kode setter du i en enkel kodeblokk med tre backticks.
  NORWEGIAN

  # Telegram rejects a message body over 4096 characters outright, so a long
  # answer is split rather than lost. The margin is for the split marker.
  MESSAGE_LIMIT = 4000

  # How many of the previous messages travel with the next one. Eleven-year-old
  # conversations wander, and the local models here have plenty of context, but
  # an unbounded transcript eventually costs more than the thread is worth.
  HISTORY_TURNS = 24

  module_function

  def config_value(env_key, path)
    from_env = ENV[env_key].to_s.strip
    return from_env unless from_env.empty?
    return "" unless File.file?(path)

    File.read(path).strip
  end

  def token = config_value("TRYMBOT_TOKEN", TOKEN_FILE)

  # Who is allowed to talk to the bot. A bot username is public — anyone who
  # finds it can open a chat — so an empty allowlist means nobody rather than
  # everybody, and `check` prints the ids that knocked so the operator can add
  # the one that is Trym.
  def allowlist
    config_value("TRYMBOT_ALLOW", ALLOW_FILE)
      .split(/[\s,]+/)
      .map(&:strip)
      .reject(&:empty?)
  end

  def allowed?(chat_id) = allowlist.include?(chat_id.to_s)

  # ---------------------------------------------------------------- providers

  # Where a reply comes from, in the order they are tried.
  #
  # ollama is first because it is the only one that keeps a child's chat log on
  # this machine. The agent CLIs behind it are coding agents rather than chat
  # models: they are slower, they cost money, and they carry tools. They run in
  # a scratch directory precisely so that a tool call, if one happens, has
  # nothing of ours to reach.
  OLLAMA_URL = ENV.fetch("TRYMBOT_OLLAMA", "http://localhost:11434")

  # Preference among whatever `ollama list` happens to hold. A bigger local
  # model writes better Norwegian, which is the whole job here.
  MODEL_PREFERENCE = %w[gemma4 gemma3 gemma2 llama3 mistral qwen].freeze

  CLI_PROVIDERS = [
    { name: "gemini", command: %w[gemini -p] },
    { name: "claude", command: %w[claude -p] },
    { name: "grok",   command: %w[grok -p] },
    { name: "codex",  command: %w[codex exec] },
  ].freeze

  CLI_TIMEOUT = Integer(ENV.fetch("TRYMBOT_CLI_TIMEOUT", "120"))

  # A cold local model pays for loading its weights on the first message of a
  # run -- llama3 takes about 50s here, a 26b considerably longer -- so this is
  # generous on purpose and the loop tells the chat it is typing meanwhile.
  OLLAMA_TIMEOUT = Integer(ENV.fetch("TRYMBOT_OLLAMA_TIMEOUT", "240"))

  def scratch_dir
    dir = File.join(CONFIG_DIR, "scratch")
    FileUtils.mkdir_p(dir)
    dir
  end

  def cli_env = { "PATH" => (CLI_PATHS + [ENV.fetch("PATH", "")]).join(":") }

  def which(command)
    CLI_PATHS.each do |dir|
      candidate = File.join(dir, command)
      return candidate if File.executable?(candidate)
    end
    nil
  end

  # The models ollama currently holds, best first. An empty list means ollama
  # is not running or has nothing pulled, which is a normal state rather than
  # an error — the CLI providers take over.
  def ollama_models
    response = http_get(URI.join(OLLAMA_URL, "/api/tags"), timeout: 5)
    names = JSON.parse(response.to_s).fetch("models", []).map { |m| m["name"].to_s }
    names.sort_by { |n| [MODEL_PREFERENCE.index { |p| n.start_with?(p) } || 99, n] }
  rescue StandardError
    []
  end

  # The models to try, best first. Pinning one with TRYMBOT_MODEL means that
  # model or nothing.
  def ollama_candidates
    pinned = ENV["TRYMBOT_MODEL"].to_s.strip
    return [pinned] unless pinned.empty?

    ollama_models - broken_models.to_a
  end

  # A model that failed to load once will fail the same way for the rest of the
  # run, and failing costs real time: gemma4:26b takes about two minutes on
  # ollama 0.33.2 to report that it cannot initialise its context. Without this
  # every message would pay that before reaching a model that works.
  def broken_models = (@broken_models ||= [])

  # messages is the Chat API shape: [{role:, content:}]. The system turn is
  # added here so no caller has to remember the brief.
  def ollama_reply(messages)
    ollama_candidates.each do |model|
      text = ollama_chat(model, messages)
      return text if text

      broken_models << model
    end
    nil
  end

  # nil means this model did not answer, and the reason is printed rather than
  # swallowed — a silent fallback is how a bot ends up quietly running on the
  # wrong backend for a week.
  def ollama_chat(model, messages)
    body = {
      model: model,
      stream: false,
      messages: [{ role: "system", content: BRIEF }] + messages,
      options: { temperature: 0.8 },
    }

    parsed = JSON.parse(http_post_json(URI.join(OLLAMA_URL, "/api/chat"), body, timeout: OLLAMA_TIMEOUT).to_s)
    if parsed["error"]
      warn "trymbot: ollama #{model} — #{parsed['error'].to_s.lines.first.to_s.strip}"
      return nil
    end

    text = parsed.dig("message", "content").to_s.strip
    warn "trymbot: ollama #{model} returned nothing" if text.empty?
    text.empty? ? nil : text
  rescue StandardError => e
    warn "trymbot: ollama #{model} — #{e.class}: #{e.message}"
    nil
  end

  # The CLIs take one prompt string rather than a transcript, so the history is
  # flattened into it. They are stateless per call for the same reason: their
  # own session memory would remember a different conversation than ours.
  def cli_prompt(messages)
    transcript = messages.map do |m|
      speaker = m[:role] == "user" ? "Trym" : NAME
      "#{speaker}: #{m[:content]}"
    end.join("\n\n")

    "#{BRIEF}\n\nSamtalen så langt:\n\n#{transcript}\n\n#{NAME}:"
  end

  def cli_reply(provider, messages)
    binary = which(provider[:command].first)
    return nil unless binary

    argv = [binary] + provider[:command][1..] + [cli_prompt(messages)]
    text = capture_with_timeout(argv)
    text.to_s.strip.empty? ? nil : text.strip
  end

  # A hung agent CLI must not wedge the poll loop, and stdin is closed so a
  # subprocess that expects a terminal exits rather than stopping on SIGTTIN.
  def capture_with_timeout(argv)
    out = nil
    Open3.popen2e(cli_env, *argv, chdir: scratch_dir, unsetenv_others: false) do |stdin, stream, thread|
      stdin.close
      reader = Thread.new { stream.read }

      unless thread.join(CLI_TIMEOUT)
        Process.kill("TERM", thread.pid) rescue nil
        reader.kill
        return nil
      end

      out = reader.value
      return nil unless thread.value.success?
    end
    out
  rescue StandardError
    nil
  end

  # Which backends could answer right now, as [name, detail] pairs. `check`
  # prints this and the poll loop reports it once at startup, because "the bot
  # is quiet" and "nothing can answer" look identical from the phone.
  def providers_available
    found = []
    model = ollama_candidates.first
    found << ["ollama", model] if model
    CLI_PROVIDERS.each { |p| found << [p[:name], which(p[:command].first)] if which(p[:command].first) }
    found
  end

  # The chain itself. Every backend gets one attempt in order, and the first
  # one to produce text wins.
  def reply_to(messages)
    text = ollama_reply(messages)
    return ["ollama", text] if text

    CLI_PROVIDERS.each do |provider|
      answer = cli_reply(provider, messages)
      return [provider[:name], answer] if answer
    end

    [nil, nil]
  end

  # ----------------------------------------------------------------- telegram

  def api_uri(method) = URI("https://api.telegram.org/bot#{token}/#{method}")

  def http_get(uri, timeout: 35)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = timeout
    http.request(Net::HTTP::Get.new(uri)).body
  end

  def http_post_json(uri, body, timeout: 35)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = timeout
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = JSON.generate(body)
    http.request(request).body
  end

  def telegram(method, params = {}, timeout: 35)
    JSON.parse(http_post_json(api_uri(method), params, timeout: timeout))
  rescue StandardError => e
    { "ok" => false, "description" => e.message }
  end

  # Telegram counts characters, not bytes, and refuses the whole message rather
  # than truncating it. Split on paragraph boundaries where one exists so a
  # code block does not land halfway through.
  def chunk(text)
    return [text] if text.length <= MESSAGE_LIMIT

    chunks = []
    remaining = text.dup
    until remaining.empty?
      break chunks << remaining if remaining.length <= MESSAGE_LIMIT

      window = remaining[0, MESSAGE_LIMIT]
      cut = window.rindex("\n\n") || window.rindex("\n") || MESSAGE_LIMIT
      chunks << remaining[0, cut].rstrip
      remaining = remaining[cut..].to_s.lstrip
    end
    chunks
  end

  def send_message(chat_id, text)
    chunk(text).each { |part| telegram("sendMessage", chat_id: chat_id, text: part) }
  end

  # ------------------------------------------------------------- conversation

  def histories = (@histories ||= Hash.new { |h, k| h[k] = [] })

  def remember(chat_id, role, content)
    log = histories[chat_id]
    log << { role: role, content: content }
    log.shift while log.length > HISTORY_TURNS
    log
  end

  # One inbound Telegram message, start to finish. Returns the reply text, or
  # nil when the message was ignored — which the loop treats as normal.
  def handle(message)
    chat_id = message.dig("chat", "id")
    text = message["text"].to_s.strip
    return nil if chat_id.nil? || text.empty?

    unless allowed?(chat_id)
      warn "trymbot: ignored chat #{chat_id} (#{message.dig('from', 'username') || 'no username'}) — not in the allowlist"
      return nil
    end

    return greet(chat_id) if text.start_with?("/start")
    return forget(chat_id) if text.start_with?("/nytt") || text.start_with?("/new")

    telegram("sendChatAction", chat_id: chat_id, action: "typing")

    source, answer = reply_to(remember(chat_id, "user", text))
    if answer.nil?
      send_message(chat_id, "B-brrzt ... hjernen min sover visst. Si ifra til mamma!")
      warn "trymbot: no provider answered for chat #{chat_id}"
      return nil
    end

    remember(chat_id, "assistant", answer)
    warn "trymbot: #{source} answered chat #{chat_id} (#{answer.length} chars)"
    send_message(chat_id, answer)
    answer
  end

  def greet(chat_id)
    text = "Hei Trym! Pip! J-jeg er Trymbot. Skal vi lage noe i dag — litt Ruby, eller en beat?"
    send_message(chat_id, text)
    histories.delete(chat_id)
    text
  end

  def forget(chat_id)
    histories.delete(chat_id)
    text = "Brrzt! Der glemte jeg alt. Hva har du lyst til å finne på nå?"
    send_message(chat_id, text)
    text
  end

  # ---------------------------------------------------------------- the loop

  # Long polling rather than a webhook: no certificate, no open port, no
  # inbound route to a laptop that moves between networks.
  def run
    abort "trymbot: no token. Put the @BotFather token in #{TOKEN_FILE} or TRYMBOT_TOKEN." if token.empty?

    me = telegram("getMe")
    abort "trymbot: Telegram rejected the token — #{me['description']}" unless me["ok"]

    warn "trymbot: @#{me.dig('result', 'username')} is listening"
    warn "trymbot: providers — #{providers_available.map(&:first).join(', ')}"
    warn "trymbot: allowlist — #{allowlist.empty? ? 'EMPTY, so every chat is ignored' : allowlist.join(', ')}"

    offset = nil
    loop do
      updates = telegram("getUpdates", { offset: offset, timeout: 30 }.compact, timeout: 45)
      unless updates["ok"]
        warn "trymbot: getUpdates failed — #{updates['description']}"
        sleep 5
        next
      end

      updates.fetch("result", []).each do |update|
        offset = update["update_id"] + 1
        message = update["message"] || update["edited_message"]
        handle(message) if message
      end
    end
  rescue Interrupt
    warn "\ntrymbot: stopped"
  end

  # ------------------------------------------------------------------ the cli

  def check
    puts "trymbot"
    puts "  token      #{token.empty? ? "MISSING — see #{TOKEN_FILE}" : 'set'}"
    puts "  allowlist  #{allowlist.empty? ? "EMPTY — every chat is ignored, see #{ALLOW_FILE}" : allowlist.join(', ')}"
    puts "  ollama     #{ollama_models.empty? ? 'not reachable or no models' : ollama_models.join(', ')}"
    CLI_PROVIDERS.each { |p| puts "  #{p[:name].ljust(10)} #{which(p[:command].first) || '-'}" }

    return if token.empty?

    me = telegram("getMe")
    puts "  telegram   #{me['ok'] ? "@#{me.dig('result', 'username')}" : "rejected — #{me['description']}"}"
  end

  # One turn through the provider chain with no Telegram in the way, so the
  # brief can be read and tuned before a token exists.
  def ask(text)
    source, answer = reply_to([{ role: "user", content: text }])
    abort "trymbot: no provider answered" if answer.nil?

    puts answer
    warn "(#{source})"
  end

  def help
    puts <<~TEXT
      Trymbot — a Telegram bot for one eleven-year-old.

        ruby trymbot.rb check          what is configured and what can answer
        ruby trymbot.rb ask "<text>"   one turn, no Telegram, for tuning the brief
        ruby trymbot.rb run            long-poll Telegram until interrupted

      The token goes in #{TOKEN_FILE} (or TRYMBOT_TOKEN), one line.
      The allowlist goes in #{ALLOW_FILE} (or TRYMBOT_ALLOW), one chat id per line.
      An empty allowlist ignores every chat: run, message the bot once, and the
      id it refuses is the one to add.

      TRYMBOT_MODEL pins an ollama model. TRYMBOT_OLLAMA moves the server.
    TEXT
  end

  def main(argv)
    case argv.first
    when "run" then run
    when "check" then check
    when "ask" then ask(argv[1..].join(" "))
    when nil, "help", "-h", "--help" then help
    else
      warn "trymbot: unknown command #{argv.first.inspect}"
      help
      exit 1
    end
  end
end

Trymbot.main(ARGV) if __FILE__ == $PROGRAM_NAME
