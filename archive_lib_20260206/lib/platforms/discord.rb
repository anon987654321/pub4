# frozen_string_literal: true

require_relative 'base'

module MASTER
  module Platforms
    # Discord integration using discordrb gem
    class Discord < Base
      def initialize(name, event_bus, token:, config: {})
        super
        @bot = nil
        @client_ready = false
      end

      def send_message(channel_id, text)
        raise "Discord client not ready" unless @client_ready
        
        retry_with_backoff do
          channel = @bot.channel(channel_id)
          raise "Channel #{channel_id} not found" unless channel
          
          # Support embeds if configured
          if config[:use_embeds]
            channel.send_embed do |embed|
              embed.description = text
              embed.color = config[:embed_color] || 0x5865F2
              embed.timestamp = Time.now
            end
          else
            channel.send_message(text)
          end
        end
      end

      def listen(&handler)
        require 'discordrb'
        
        @bot = Discordrb::Bot.new(token: @token)
        
        # Handle regular messages
        @bot.message do |event|
          next if event.author.bot_account? # Ignore bots
          
          # Check whitelist if configured
          if config[:channel_whitelist] && !config[:channel_whitelist].empty?
            next unless config[:channel_whitelist].include?(event.channel.id.to_s)
          end
          
          message_data = {
            channel_id: event.channel.id.to_s,
            user_id: event.author.id.to_s,
            text: event.message.content,
            username: event.author.username,
            mention: event.message.mentions.any? { |u| u.id == @bot.profile.id }
          }
          
          handler.call(message_data) if handler
          handle_incoming(message_data)
        end
        
        # Handle slash commands
        @bot.application_command(:help) do |event|
          event.respond(content: "MASTER bot - AI assistant powered by Constitutional AI")
        end
        
        @bot.ready do
          @client_ready = true
          emit(:discord_ready, { user: @bot.profile.username })
        end
        
        # Run in background thread
        Thread.new { @bot.run }
      end

      def verify_webhook(signature, body)
        # Discord uses Ed25519 signature verification
        # This requires the public key from Discord application settings
        return true unless config[:verify_signatures]
        
        require 'openssl'
        public_key = config[:public_key]
        return false unless public_key
        
        begin
          timestamp = signature[:timestamp]
          signature_hex = signature[:signature]
          
          message = timestamp + body
          signature_bytes = [signature_hex].pack('H*')
          
          key = OpenSSL::PKey::Ed25519.new([public_key].pack('H*'))
          key.verify(nil, signature_bytes, message)
        rescue => e
          emit(:verification_error, { platform: 'discord', error: e.message })
          false
        end
      end

      def on_stop
        @bot&.stop
        @client_ready = false
        super
      end
    end
  end
end
