# frozen_string_literal: true

require_relative "../../io/irc"
require_relative "chat_services"

module Master
  module CLI
    module CommandRegistry
      module_function

      CHAT_VERBS = (%w[connect join part say msg me names topic list nick irc chat] + CHAT_SERVICE_VERBS).freeze
      CHAT_ROOM = Master::Io::Irc::ROOM

      CHAT_HELP = {
        "connect" => {
          summary: "connect to a chat service (IRC first); read-only until /chat speak on",

          detail: [
            "/connect <host>[:port] [nick] — IRC over TLS (certificate and hostname verified); " \
             "nick defaults to MASTER_IRC_NICK, then the saved one.",

            "/connect <host> <nick> --plain — plain text, only when asked for by name.",
            "/connect telegram — Telegram Bot API, read-only; token from MASTER_TELEGRAM_TOKEN, never shown. " \
             "/say <chat id or @name> <text> after /chat speak on.",
            "/connect slskd — your own slskd (MASTER_SLSKD_URL, MASTER_SLSKD_API_KEY); then /slsk. " \
             "/connect whatsapp is reserved; not available yet.",
            "MASTER_IRC_PASSWORD, when set, logs in with SASL PLAIN and is never shown.",
            "Your IP address is visible to the network. " \
             "MASTER_IRC_LOG=1 logs under .master/irc/ (0600); off by default.",
          ],
        },

        "join" => {
          summary: "join channels",
          detail: [
            "/join #chan[,#chan]",
          ],
        },

        "part" => {
          summary: "leave a channel",
          detail: [
            "/part [#chan]",
          ],
        },

        "say" => {
          summary: "send one line to a channel, explicitly",
          detail: [
            "/say [#chan] <text> — needs /chat speak on. Published at once, cannot be taken back.",
            "MASTER never writes to a room on its own and no model tool can.",
          ],
        },

        "msg" => {
          summary: "send one direct message to an IRC nick, explicitly",
          detail: [
            "/msg <nick> <text> — IRC only; needs /chat speak on. Published at once, cannot be taken back.",
            "A direct message is never inferred from ordinary conversation and no model tool can send it.",
          ],
        },

        "me" => {
          summary: "send an action line, explicitly",
          detail: [
            "/me [#chan] <text> — needs /chat speak on.",
          ],
        },

        "names" => {
          summary: "list who is in a channel",
          detail: [
            "/names [#chan]",
          ],
        },

        "topic" => {
          summary: "show a channel topic",
          detail: [
            "/topic [#chan] — shown; /topic [#chan] <text> sets it and needs speak on.",
          ],
        },

        "list" => {
          summary: "list busy channels, limited",
          detail: [
            "/list [pattern] — channels over 100 users by default; the first 20 are shown.",
          ],
        },

        "nick" => {
          summary: "change nick",
          detail: [
            "/nick <new>",
          ],
        },

        "irc" => {
          summary: "IRC session control (same as /chat)",
          detail: [
            "/irc [status] — connection, nick, channels, read-only or can-send.",
            "/irc speak on|off, /irc quit [msg], /irc summarize.",
          ],
        },

        "chat" => {
          summary: "every chat transport: status, speak, quit, summarize",

          detail: [
            "/chat status — each transport, nick, channels, mode.",
            "/chat speak on|off — allow explicit /say, /me and /msg (off at every new connection).",
            "/chat quit [msg] — disconnect (/quit still exits MASTER).",
            "/chat summarize — the operator asks the model to summarize recent lines, " \
             "sent as quoted untrusted data.",
          ],
        },
      }.merge(CHAT_SERVICE_HELP).freeze

      CHAT_ACTIONS = {
        "join" => :chat_join, "part" => :chat_part, "say" => :chat_say_line, "msg" => :chat_private_message, "me" => :chat_me_line,
        "names" => :chat_names, "topic" => :chat_topic_line, "list" => :chat_busy_channels, "nick" => :chat_nick,
        "speak" => :chat_speak, "quit" => :chat_quit, "disconnect" => :chat_quit, "summarize" => :chat_summary,
      }.freeze

      CHAT_USAGE = "usage: /chat status | speak on|off | quit [msg] | summarize"

      def chat_verbs(dependencies)
        deps = dependencies.slice(:bus, :agent, :config)
        CHAT_VERBS.to_h do |verb|
          [verb, Command.new { |context| dispatch_chat(verb, ctx: context, **deps) }]
        end
      end

      def dispatch_chat(verb, ctx: nil, **deps)
        args = arg_for(ctx)
        return chat_connect(args, bus: deps[:bus], config: deps[:config]) if verb == "connect"
        return chat_slsk(args) if verb == "slsk"

        if verb.start_with?("connect:")
          return chat_connect_form(verb.delete_prefix("connect:"), args, bus: deps[:bus], config: deps[:config])
        end

        if %w[irc chat].include?(verb)
          word, rest = args.split(/\s+/, 2)
          verb = word.to_s.downcase
          args = rest.to_s
        end
        verb = "status" if verb.empty?
        return Io::Chat.status_lines.join("\n") if verb == "status"

        chat = Io::Chat.current
        return "chat0: not connected; /connect <host> <nick>" unless chat

        chat_act(chat, verb, args.strip, agent: deps[:agent])
      rescue Io::Chat::ReadOnly, ArgumentError, RuntimeError, SystemCallError, IOError, OpenSSL::OpenSSLError => e
        "chat0: #{Io::Chat::Policy.sanitize(e.message, max: 200)}"
      end

      def chat_connect(args, bus:, config:)
        service = Io::Chat.service_for(args)
        return "#{service}0: not available yet" unless Io::Chat.available?(service)
        return chat_connect_service(service, bus:) unless service == "irc"

        chat_connect_irc(args.split, bus:, config:)
      end

      # Each verb is a named handler; the table above says which.
      def chat_act(chat, verb, args, agent:)
        handler = CHAT_ACTIONS[verb]
        return CHAT_USAGE unless handler
        return "#{chat.name}0: /#{verb} is not available on this transport" if CHAT_IRC_ONLY[verb] && !chat.respond_to?(CHAT_IRC_ONLY[verb])

        send(handler, chat, args, agent:)
      end

      def chat_join(chat, args, **)
        chat.join(args.split(/[,\s]+/).reject(&:empty?))
        "irc0: joining #{args}"
      end

      def chat_part(chat, args, **)
        chat.part(args.split.first || chat.last_room)
        "irc0: leaving"
      end

      def chat_say_line(chat, args, **) = chat_say(chat, args, action: false)
      def chat_me_line(chat, args, **) = chat_say(chat, args, action: true)

      def chat_private_message(chat, args, **)
        return "chat0: /msg is available on IRC only" unless chat.is_a?(Io::Irc)

        recipient, text = args.split(/\\s+/, 2)
        raise ArgumentError, "usage: /msg <nick> <text>" if recipient.to_s.empty? || text.to_s.strip.empty?
        raise ArgumentError, "bad nick" unless recipient.match?(Io::Irc::NICK)

        chat.send_text(recipient, text)
        "irc0: -> #{recipient} #{Io::Chat::Policy.sanitize(text)}"
      end

      def chat_names(chat, args, **)
        chat.names(args.split.first)
        "irc0: asked for names"
      end

      def chat_topic_line(chat, args, **) = chat_topic(chat, args)

      def chat_busy_channels(chat, args, **)
        chat.list(args.empty? ? nil : args)
        "irc0: asked for a limited list"
      end

      def chat_nick(chat, args, **)
        chat.change_nick(args.split.first)
        "irc0: asked for nick #{args.split.first}"
      end

      def chat_quit(chat, args, **)
        chat.disconnect(args)
        "irc0: bye"
      end

      def chat_room_and_text(chat, args)
        return chat.parse_say(args) if chat.respond_to?(:parse_say)

        first, rest = args.split(/\s+/, 2)
        first.to_s.match?(CHAT_ROOM) ? [first, rest.to_s] : [chat.last_room, args]
      end

      def chat_say(chat, args, action:)
        room, text = chat_room_and_text(chat, args)
        raise ArgumentError, "usage: /say [#chan] <text>" if room.nil? || text.strip.empty?

        chat.send_text(room, text, action:)
        "#{room} #{action ? '*' : "<#{chat.nick}>"} #{Io::Chat::Policy.sanitize(text)}"
      end

      def chat_topic(chat, args)
        room, text = chat_room_and_text(chat, args)
        chat.topic(room, text.empty? ? nil : text)
        "irc0: topic requested"
      end

      def chat_speak(chat, args, **)
        raise ArgumentError, "usage: /chat speak on|off" unless %w[on off].include?(args)

        Io::Chat.live.each { |transport| transport.policy.speak = (args == "on") }
        reminder = "; every line still needs an explicit /say" if chat.policy.speak?

        "#{chat.name}0: #{chat.policy.mode}#{reminder}"
      end

      def chat_summary(chat, _args = nil, agent: nil)
        return "chat0: no model attached" unless agent

        lines = []
        chat.each_event do |event|
          lines << "#{event.room} <#{event.nick}> #{event.text}" if %i[message action].include?(event.kind)
        end
        return "chat0: nothing to summarize" if lines.empty?

        quoted = Io::Chat::Policy.untrusted_block(lines.last(50), source: chat.name)
        agent.ask_once("Summarize these chat lines in three sentences.\n#{quoted}")
      end
    end
  end
end
