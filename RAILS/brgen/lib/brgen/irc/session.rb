# frozen_string_literal: true

module Brgen
  module Irc
    # One IRC client connection as a state machine. #handle(line) returns the lines
    # to send back and performs bridge side effects; #poll returns new web-side
    # messages to relay. No sockets here, so it is fully unit-testable.
    class Session
      SERVER = "irc.brgen.no"

      attr_reader :nick, :channels

      def initialize(bridge:, server_name: SERVER)
        @bridge = bridge
        @server = server_name
        @nick = nil
        @user = nil
        @registered = false
        @channels = {} # "#slug" => { channel:, last_id: }
      end

      def registered? = @registered

      def handle(raw)
        message = Message.parse(raw)
        return [] unless message

        case message.command
        when "NICK"    then on_nick(message)
        when "USER"    then on_user(message)
        when "PING"    then [ build("PONG", [ message.params.first || @server ]) ]
        when "JOIN"    then on_join(message)
        when "PART"    then on_part(message)
        when "PRIVMSG" then on_privmsg(message)
        when "NAMES"   then names(message.params.first)
        when "QUIT"    then @channels.clear; [ build("ERROR", [ "Closing link" ]) ]
        when "CAP"     then [] # no capabilities negotiated
        else []
        end
      end

      # Called on a timer by the server: relay anything posted on the web side.
      def poll
        out = []
        @channels.each_value do |state|
          @bridge.messages_since(state[:channel], state[:last_id]).each do |m|
            state[:last_id] = m[:id]
            next if m[:nick] == @nick # don't echo our own line back

            out << build("PRIVMSG", [ "##{state[:channel].slug}", m[:text] ], prefix: m[:nick])
          end
        end
        out
      end

      private

      def on_nick(message)
        @nick = message.params.first
        try_register
      end

      def on_user(message)
        @user = message.params.first
        try_register
      end

      def try_register
        return [] if @registered || @nick.to_s.empty? || @user.to_s.empty?

        @registered = true
        [
          numeric("001", "Welcome to the brgen IRC bridge, #{@nick}"),
          numeric("002", "Your host is #{@server}"),
          numeric("003", "brgen bridges a city's channels to IRC"),
          numeric("004", "#{@server} brgen-bridge o ov"),
          numeric("375", "- #{@server} -"),
          numeric("372", "- IRC's honesty, a city's chat. Try /join #brgen"),
          numeric("376", "End of /MOTD command"),
        ]
      end

      def on_join(message)
        return [] unless @registered

        channel = @bridge.channel_for(message.params.first)
        return [ numeric("403", "No such channel", extra: message.params.first) ] unless channel

        cname = @bridge.channel_name(channel)
        history = @bridge.history(channel)
        @channels[cname] = { channel: channel, last_id: history.map { |h| h[:id] }.max.to_i }

        lines = [ build("JOIN", [ cname ], prefix: user_prefix) ]
        lines << numeric("332", @bridge.topic(channel), extra: cname)
        lines.concat(names(cname))
        history.each { |h| lines << build("PRIVMSG", [ cname, h[:text] ], prefix: h[:nick]) }
        lines
      end

      def on_part(message)
        cname = message.params.first
        @channels.delete(cname)
        [ build("PART", [ cname ], prefix: user_prefix) ]
      end

      def on_privmsg(message)
        return [] unless @registered

        target = message.params.first
        text = message.params.last
        state = @channels[target]
        return [] unless state # channel messages only for now

        posted = @bridge.post(state[:channel], @nick, text)
        state[:last_id] = posted.id if posted.respond_to?(:id) # so poll never echoes it back
        [] # IRC never echoes your own PRIVMSG to you
      end

      def names(cname)
        state = @channels[cname]
        channel = state ? state[:channel] : @bridge.channel_for(cname)
        return [] unless channel

        nicks = @bridge.roster(channel).map { |r| "#{r[:mode]}#{r[:nick]}" }
        nicks << @nick if @nick && nicks.none? { |n| n.sub(/\A[@+]/, "") == @nick }
        [
          build("353", [ @nick, "=", cname, nicks.join(" ") ]),
          build("366", [ @nick, cname, "End of /NAMES list" ])
        ]
      end

      def numeric(code, text, extra: nil)
        params = [ @nick || "*" ]
        params << extra if extra
        params << text
        build(code, params)
      end

      def build(command, params, prefix: @server)
        Message.build(command, params, prefix: prefix)
      end

      def user_prefix = "#{@nick}!#{@user}@brgen"
    end
  end
end
