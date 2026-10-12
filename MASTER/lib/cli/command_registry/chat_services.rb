# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # Help and handlers for the services beside IRC (Telegram, slskd) and for
      # the protocol-qualified /connect:irc|slsk|telegram forms.
      CHAT_SERVICE_VERBS = %w[slsk connect:irc connect:slsk connect:telegram].freeze

      CHAT_SERVICE_HELP = {
        "connect:irc" => {
          summary: "connect to IRC and join channels once registered",
          detail: [
            "/connect:irc <host>[:port] <nick> [#chan ...] [--plain] — e.g. /connect:irc irc.libera.chat heyhey123 #help.",
            "Same as /connect <host> <nick>: TLS 6697, certificate verified, read-only, speak off; " \
             "the channels are joined after the server welcomes you.",
          ],
        },
        "connect:slsk" => {
          summary: "attach to your slskd and join Soulseek rooms",
          detail: [
            "/connect:slsk <nick> [#room ...] — e.g. /connect:slsk heyhey123 #indie #punk.",
            "slskd owns the Soulseek login, so the nick is only a label; rooms are joined through slskd's rooms API.",
            "MASTER_SLSKD_URL and MASTER_SLSKD_API_KEY as for /connect slskd; localhost only. " \
             "Read-only, speak off, each download confirmed by /slsk get <n>.",
          ],
        },
        "connect:telegram" => {
          summary: "attach the Telegram bot (read-only)",
          detail: ["/connect:telegram — same as /connect telegram; a bot joins no rooms, so it takes no arguments."],
        },
        "slsk" => {
          summary: "Soulseek through your slskd: search, browse, rooms, queue, get",
          detail: [
            "/slsk search <text>, /slsk results, /slsk get <n> — one numbered result, never bulk; " \
             "audio only, 300 MB cap, into a 0700 quarantine outside the repo.",
            "/slsk browse <user>, rooms, room <name>, pm <user>, join <room>, leave <room>, queue, status.",
            "/say room:<name> <text> or /say pm:<user> <text> needs /chat speak on.",
          ],
        },
      }.freeze

      # Verbs a transport may not implement (IRC-only), by the method they need.
      CHAT_IRC_ONLY = { "names" => :names, "topic" => :topic, "list" => :list, "nick" => :change_nick }.freeze

      def chat_connect_form(proto, args, bus:, config:)
        case proto
        when "irc" then chat_connect_irc(args.split, bus:, config:)
        when "slsk", "slskd" then chat_connect_slsk(args.split, bus:)
        when "telegram" then chat_connect_telegram(args, bus:)
        else "chat0: unknown protocol #{Io::Chat::Policy.sanitize(proto, max: 20)}; irc, slsk or telegram"
        end
      end

      def chat_connect_irc(words, bus:, config:)
        plain = !words.delete("--plain").nil?
        host = words.shift
        nick = words.shift unless words.first.to_s.match?(CHAT_ROOM)
        chans = words
        nick ||= ENV["MASTER_IRC_NICK"] || config&.[]("irc_nick")
        if nick.to_s.empty? || host.nil?
          return "irc0: which nick? /connect:irc #{host || '<host>'} <nick> [#chan ...], or set MASTER_IRC_NICK"
        end

        bad = chans.reject { |chan| chan.match?(CHAT_ROOM) }
        return "irc0: not a channel: #{Io::Chat::Policy.sanitize(bad.first, max: 40)}" if bad.any?

        Io::Chat.transport("irc", bus:).connect(host, nick:, plain:, join: chans)
        (config["irc_nick"] = nick; config.save!) if config
        Io::Chat.status_lines.join("\n")
      end

      # slskd owns the Soulseek login (its own config); the nick here is a label.
      def chat_connect_slsk(words, bus:)
        nick = words.shift unless words.first.to_s.start_with?("#")
        rooms = words.map { |word| word.delete_prefix("#") }
        if rooms.any? { |room| room.empty? || room.match?(/[\s,]/) }
          return "slsk0: not a room: #{Io::Chat::Policy.sanitize(words.first, max: 40)}"
        end

        Io::Chat.transport("slskd", bus:).connect(label: nick, rooms:)
        Io::Chat.status_lines.join("\n")
      rescue Io::Chat::Slskd::Unavailable, Io::Chat::Http::Error => e
        "slsk0: #{Io::Chat::Policy.sanitize(e.message, max: 200)}"
      end

      def chat_connect_telegram(args, bus:)
        return "telegram0: a bot joins no rooms; /connect:telegram takes no arguments" unless args.empty?

        chat_connect_service("telegram", bus:)
      end

      def chat_connect_service(service, bus:)
        Io::Chat.transport(service, bus:).connect
        Io::Chat.status_lines.join("\n")
      rescue Io::Chat::Telegram::Unavailable, Io::Chat::Slskd::Unavailable, Io::Chat::Http::Error => e
        "#{service}0: #{Io::Chat::Policy.sanitize(e.message, max: 200)}"
      end

      def chat_slsk(args)
        slskd = Io::Chat.find("slskd")
        return "slsk0: not connected; /connect slskd" unless slskd&.live?

        slskd.command(args).join("\n")
      end
    end
  end
end
