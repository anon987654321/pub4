# frozen_string_literal: true

require_relative "../chat"

module Master
  module Io
    class Irc < Chat::Transport
      # What the reader thread does with each parsed server line. The only
      # reply it ever writes is PONG (and the CAP/SASL/NICK registration steps).
      module Events
        DISPATCH = {
          "PING" => :on_ping, "CAP" => :handle_auth, "AUTHENTICATE" => :handle_auth,
          "903" => :handle_auth, "904" => :handle_auth, "905" => :handle_auth,
          "906" => :handle_auth, "907" => :handle_auth, "001" => :welcome,
          "432" => :retry_nick, "433" => :retry_nick, "436" => :retry_nick,
          "JOIN" => :on_join, "PART" => :on_part, "KICK" => :kicked, "QUIT" => :on_quit,
          "NICK" => :renamed, "MODE" => :on_mode, "TOPIC" => :on_topic, "332" => :on_topic,
          "353" => :on_names, "366" => :on_names_end, "322" => :list_entry, "323" => :on_list_end,
          "PRIVMSG" => :message, "NOTICE" => :message, "ERROR" => :on_error
        }.freeze

        private

        def handle(msg)
          meth = DISPATCH[msg.command] || (:numeric_notice if msg.command.match?(/\A[45]\d\d\z/))
          send(meth, msg) if meth
        end

        def on_ping(msg) = raw(Wire.line("PONG", msg.params.last.to_s))
        def on_join(msg) = joined(msg.nick, msg.params.first.to_s)
        def on_part(msg) = parted(msg.nick, msg.params.first.to_s, msg.params[1])
        def on_names(msg) = (@names[msg.params[2]] ||= []).concat(msg.params.last.split)
        def on_names_end(msg) = names_done(msg.params[1])
        def on_error(msg) = emit(:info, text: msg.params.last, line: "irc0: server error: #{clean(msg.params.last)}")

        def on_quit(msg)
          why = clean(msg.params.last)
          emit(:quit, nick: msg.nick, text: msg.params.last, line: "irc0: #{clean(msg.nick)} quit (#{why})")
        end

        def on_mode(msg) = emit(:mode, room: msg.params.first, nick: msg.nick, text: msg.params[1..].join(" "))

        def on_topic(msg)
          room = msg.command == "332" ? msg.params[1] : msg.params.first
          emit(:topic, room:, text: msg.params.last, line: "#{clean(room)} topic: #{clean(msg.params.last)}")
        end

        def on_list_end(_msg)
          emit(:info, text: "list end", line: "irc0: list end, #{@listed} channels") if @listed.positive?
        end

        def clean(text) = Chat::Policy.sanitize(text, max: 200)

        def handle_auth(msg)
          case msg.command
          when "CAP"
            verdict = msg.params[1].to_s.upcase
            return unless %w[ACK NAK].include?(verdict)

            verdict == "ACK" && msg.params.last.to_s.split.include?("sasl") ? raw("AUTHENTICATE PLAIN") : raw("CAP END")
          when "AUTHENTICATE"
            Wire.sasl_plain(@base_nick, @env["MASTER_IRC_PASSWORD"]).each { |l| raw(l) } if msg.params.first == "+"
          else
            raw("CAP END")
            emit(:info, text: "sasl", line: "irc0: sasl #{msg.command == '903' ? 'login ok' : 'login failed'}")
          end
        end

        def welcome(msg)
          @nick = msg.params.first
          @registered = true
          emit(:info, text: "registered", line: "irc0: registered as #{clean(@nick)}")
        end

        def retry_nick(_msg = nil)
          return if @registered

          @nick_try += 1
          return close_io if @nick_try > NICK_TRIES

          @nick = "#{@base_nick}#{@nick_try}"
          raw(Wire.line("NICK", @nick))
        end

        def joined(who, room)
          @channels[room] ||= Set.new if who == @nick
          @channels[room]&.add(who)
          emit(:join, room:, nick: who, line: "#{clean(room)} join #{clean(who)}")
        end

        def parted(who, room, why)
          who == @nick ? @channels.delete(room) : @channels[room]&.delete(who)
          emit(:part, room:, nick: who, text: why, line: "#{clean(room)} part #{clean(who)}")
        end

        def kicked(msg)
          room, who = msg.params
          @channels.delete(room) if who == @nick
          emit(:part, room:, nick: who, text: msg.params[2], line: "#{clean(room)} kick #{clean(who)} by #{clean(msg.nick)}")
        end

        def renamed(msg)
          @nick = msg.params.last if msg.nick == @nick
          emit(:nick, nick: msg.nick, text: msg.params.last, line: "irc0: #{clean(msg.nick)} is now #{clean(msg.params.last)}")
        end

        def names_done(room)
          list = @names.delete(room) || []
          @channels[room]&.merge(list.map { |n| n.sub(/\A[~&@%+]+/, "") })
          shown = list.first(60).join(" ")
          emit(:names, room:, text: shown, line: "#{clean(room)} #{list.size} names: #{clean(shown)}")
        end

        def list_entry(msg)
          @listed += 1
          return if @listed > LIST_SHOWN

          emit(:info, text: msg.params[1], line: "irc0: #{clean(msg.params[1])} #{clean(msg.params[2])} users #{clean(msg.params.last)}")
        end

        # Answers nothing: a CTCP request is shown as a line and ignored.
        def message(msg)
          room = msg.params.first
          room = msg.nick if room == @nick
          text = msg.params.last.to_s
          if (ctcp = text.match(/\A\x01(\w+) ?(.*?)\x01?\z/m))
            return emit(:action, room:, nick: msg.nick, text: ctcp[2]) if ctcp[1] == "ACTION"

            return emit(:info, nick: msg.nick, text: ctcp[1], line: "irc0: ctcp #{clean(ctcp[1])} from #{clean(msg.nick)} ignored")
          end
          emit(msg.command == "NOTICE" ? :notice : :message, room: room || @host, nick: msg.nick || @host, text:)
        end

        def numeric_notice(msg)
          return unless msg.command.match?(/\A[45]\d\d\z/)

          emit(:info, text: msg.params.last, line: "irc0: #{msg.command} #{clean(msg.params.last)}")
        end
      end
    end
  end
end
