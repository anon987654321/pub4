# frozen_string_literal: true

module Brgen
  module Irc
    # The seam between the IRC protocol and brgen's own models. Everything the
    # session needs from the app goes through here, so Session can be unit-tested
    # against a fake bridge with no database or socket. brgen channels are
    # anonymous by design, so a web viewer sees an IRC poster as an anon handle —
    # the nick is preserved on the IRC side, not forced onto the web side.
    class Bridge
      def default_city
        ::City.find_by(domain: "brgen.no")
      end

      # Only the known city channels are joinable; a guessed #slug returns nil.
      def channel_for(name)
        slug = name.to_s.sub(/\A#/, "")
        return nil unless ::Conversation::CHANNELS.key?(slug)

        ::Conversation.find_or_create_channel(slug, city: default_city)
      end

      def channel_name(channel)
        "##{channel.slug}"
      end

      def topic(channel)
        ::Conversation.channel_blurb(channel.slug)
      end

      # A user row to author a bridged message. One per distinct nick, namespaced
      # so it never collides with a web account.
      def bridged_user(nick)
        username = "#{nick}[irc]"
        ::User.find_or_create_by!(username: username) do |user|
          user.email_address = "irc-#{nick.downcase}-#{SecureRandom.hex(3)}@bridge.invalid"
          user.password = SecureRandom.hex(16)
          user.bot = false
        end
      end

      def post(channel, nick, text)
        sender = bridged_user(nick)
        channel.join!(sender)
        channel.messages.create!(sender: sender, message_type: "text", content: text)
      end

      def history(channel, limit: 20)
        channel.messages.unexpired.order(created_at: :desc).limit(limit).reverse.map { |m| line_for(m) }
      end

      # Web -> IRC relay: everything newer than the last id the client has seen.
      def messages_since(channel, last_id)
        channel.messages.visible.unexpired.where("id > ?", last_id.to_i).order(:id).map { |m| line_for(m) }
      end

      def roster(channel)
        channel.conversation_participants.by_rank.includes(:user).map do |member|
          { nick: irc_nick(member.user), mode: member.mode_prefix }
        end
      end

      def line_for(message)
        { id: message.id, nick: irc_nick(message.sender), text: message.content.to_s }
      end

      def irc_nick(user)
        raw = user.try(:channel_handle).presence || user.try(:username).presence || "anon"
        raw.to_s.sub(/\[irc\]\z/, "").gsub(/\s+/, "_")
      end
    end
  end
end
