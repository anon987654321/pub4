# frozen_string_literal: true

require_relative "transport"
require_relative "http"
require_relative "telegram_limiter"

module Master
  module Io
    module Chat
      # Telegram through the official Bot API only (https://core.telegram.org/bots/api):
      # HTTPS long polling, no webhook, no user-account (MTProto) access. A bot
      # sees a group's messages only when its privacy mode allows; that is
      # Telegram's rule, not ours. Read-only until `speak on` (Policy); the token
      # comes from MASTER_TELEGRAM_TOKEN and appears in no status or error string.
      class Telegram < Transport
        API = "https://api.telegram.org"
        TOKEN_SHAPE = /\A\d{3,}:[A-Za-z0-9_-]{8,}\z/
        POLL_SECONDS = 25
        UPDATE_KEYS = %w[message edited_message channel_post edited_channel_post].freeze
        MAX_RETRY_WAIT = 60

        class Unavailable < RuntimeError; end

        attr_reader :offset, :bot, :last_room

        def initialize(token: ENV["MASTER_TELEGRAM_TOKEN"], base: API, http: nil, limiter: nil,
                       sleeper: Kernel.method(:sleep), **opts)
          super(**opts)
          @token = token.to_s.strip
          @http = http || Http.new(base:, secrets: -> { [@token] }, read_timeout: POLL_SECONDS + 10)
          @limiter = limiter || TelegramLimiter.new(sleeper:)
          @sleeper = sleeper
          @offset = 0
          @groups = {}
          @live = false
        end

        def name = "telegram"
        def capabilities = %i[read send]
        def live? = @live

        def connect(_target = nil, poll: true, **)
          raise Unavailable, "MASTER_TELEGRAM_TOKEN is not set" if @token.empty?
          raise Unavailable, "MASTER_TELEGRAM_TOKEN is not a bot token" unless @token.match?(TOKEN_SHAPE)

          @bot = call("getMe")
          @live = true
          show("tg0: @#{Policy.sanitize(@bot["username"], max: 40)} attached (#{policy.mode}, long poll)")
          start_poll if poll
          self
        end

        def disconnect(_message = nil)
          @live = false
          @thread&.join(1)
          @thread = nil
          show("tg0: detached")
        end

        def nick = "@#{Policy.sanitize(@bot&.fetch("username", nil) || "bot", max: 40)}"

        # `/say <chat id or @name> <text>`; a bare text goes to the last chat heard from.
        def parse_say(args)
          first, rest = args.split(/\s+/, 2)
          return [first, rest.to_s] if first.to_s.match?(/\A(-?\d+|@\w{4,})\z/)

          [@last_room, args]
        end

        def join(_room) = raise(Unavailable, "a bot cannot join chats; add it from Telegram")
        def part(_room) = raise(Unavailable, "a bot cannot leave chats from here")

        def status
          "tg0: telegram #{@live ? "attached" : "detached"} #{policy.mode} " \
            "token #{@token.empty? ? "unset" : "set"} offset #{@offset} chats #{@groups.size}"
        end

        # One getUpdates round. Returns the number of updates handled, or 0 after
        # waiting out a 429.
        def poll_once(timeout: POLL_SECONDS)
          res = @http.post(path("getUpdates"),
                           { offset: @offset, timeout:, allowed_updates: UPDATE_KEYS }, timeout: timeout + 10)
          return rate_limited(res) if res.status == 429

          raise Http::Error, api_error(res) unless res.ok? && res.json.is_a?(Hash) && res.json["ok"]

          updates = Array(res.json["result"])
          updates.each { |update| handle(update) }
          updates.size
        end

        private

        # `text` goes to a numeric chat id or @channelusername.
        def deliver(room, text, action: false)
          target = room.to_s
          raise ArgumentError, "chat must be a numeric id or @username" unless target.match?(/\A(-?\d+|@\w{4,})\z/)

          @limiter.wait(target, group: target.start_with?("@") || target.start_with?("-"))
          text = "/me #{text}" if action
          send_message(target, text, retried: false)
        end

        def send_message(target, text, retried:)
          res = @http.post(path("sendMessage"), { chat_id: target, text: })
          if res.status == 429 && !retried
            @sleeper.call(retry_after(res))
            return send_message(target, text, retried: true)
          end
          raise Http::Error, api_error(res) unless res.ok?

          res
        end

        def start_poll
          @thread = Thread.new do
            while @live
              begin
                poll_once
              rescue StandardError => e
                show("tg0: poll error #{@http.redact(e.message)}")
                @sleeper.call(5)
              end
            end
          end
        end

        def call(method)
          res = @http.get(path(method))
          raise Http::Error, api_error(res) unless res.ok? && res.json.is_a?(Hash) && res.json["ok"]

          res.json["result"]
        end

        def path(method) = "/bot#{@token}/#{method}"

        def api_error(res)
          detail = res.json.is_a?(Hash) ? res.json["description"] : nil
          @http.redact("telegram http #{res.status}: #{Policy.sanitize(detail || "no detail", max: 120)}")
        end

        def retry_after(res)
          secs = res.json.is_a?(Hash) ? res.json.dig("parameters", "retry_after").to_i : 0
          secs.clamp(1, MAX_RETRY_WAIT)
        end

        def rate_limited(res)
          wait = retry_after(res)
          show("tg0: rate limited, waiting #{wait}s")
          @sleeper.call(wait)
          0
        end

        def handle(update)
          id = update["update_id"].to_i
          @offset = id + 1 if id >= @offset
          key = UPDATE_KEYS.find { |k| update[k].is_a?(Hash) }
          return unless key

          msg = update[key]
          chat = msg["chat"] || {}
          @groups[chat["id"]] = chat["type"]
          @last_room = chat["id"].to_s
          body = msg["text"] || msg["caption"] || "[#{media_kind(msg)}]"
          mark = key.start_with?("edited") ? "(edited) " : ""
          emit(:message, room: room_label(chat), nick: sender_name(msg), text: "#{mark}#{body}",
                         line: nil)
        end

        def media_kind(msg) = (%w[photo voice audio video document sticker] & msg.keys).first || "non-text"

        def room_label(chat)
          label = chat["title"] || (chat["username"] && "@#{chat["username"]}") || chat["first_name"] || "chat"
          "#{label}/#{chat["id"]}"
        end

        def sender_name(msg)
          from = msg["from"] || msg["sender_chat"] || {}
          from["username"] || from["first_name"] || from["title"] || "?"
        end

        def default_line(event)
          "tg0: #{event.room} <#{event.nick}> #{event.text}"
        end
      end
    end
  end
end
