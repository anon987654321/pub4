# frozen_string_literal: true

require_relative 'base'

module MASTER
  module Platforms
    # Telegram integration using telegram-bot-ruby gem
    class Telegram < Base
      def initialize(name, event_bus, token:, config: {})
        super
        @bot = nil
      end

      def send_message(channel_id, text)
        raise "Telegram client not ready" unless @bot
        
        retry_with_backoff do
          # Support reply markup if configured
          if config[:reply_markup]
            @bot.api.send_message(
              chat_id: channel_id,
              text: text,
              reply_markup: config[:reply_markup],
              parse_mode: config[:parse_mode] || 'Markdown'
            )
          else
            @bot.api.send_message(
              chat_id: channel_id,
              text: text,
              parse_mode: config[:parse_mode] || 'Markdown'
            )
          end
        end
      end

      def listen(&handler)
        require 'telegram/bot'
        
        Telegram::Bot::Client.run(@token) do |bot|
          @bot = bot
          emit(:telegram_ready, { username: bot.api.get_me['result']['username'] })
          
          bot.listen do |message|
            # Handle different message types
            case message
            when Telegram::Bot::Types::Message
              # Check whitelist if configured
              if config[:chat_whitelist] && !config[:chat_whitelist].empty?
                next unless config[:chat_whitelist].include?(message.chat.id.to_s)
              end
              
              # Extract text from message
              text = message.text || message.caption || ''
              next if text.empty?
              
              message_data = {
                channel_id: message.chat.id.to_s,
                user_id: message.from.id.to_s,
                text: text,
                username: message.from.username || message.from.first_name,
                is_command: text.start_with?('/'),
                chat_type: message.chat.type
              }
              
              # Handle bot commands
              if message_data[:is_command]
                handle_telegram_command(bot, message, text)
              end
              
              handler.call(message_data) if handler
              handle_incoming(message_data)
              
            when Telegram::Bot::Types::CallbackQuery
              # Handle inline keyboard callbacks
              bot.api.answer_callback_query(callback_query_id: message.id)
              
              callback_data = {
                channel_id: message.message.chat.id.to_s,
                user_id: message.from.id.to_s,
                text: "/callback #{message.data}",
                username: message.from.username || message.from.first_name,
                is_command: true
              }
              
              handler.call(callback_data) if handler
              handle_incoming(callback_data)
            end
          end
        end
      end

      def verify_webhook(signature, body)
        # Telegram webhook verification uses secret token
        return true unless config[:verify_signatures]
        
        expected_token = config[:webhook_secret]
        return false unless expected_token
        
        signature == expected_token
      end

      private

      def handle_telegram_command(bot, message, text)
        case text
        when '/start'
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "Welcome to MASTER bot! Send me a message to chat."
          )
        when '/help'
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "MASTER - AI assistant powered by Constitutional AI\n\nJust send me a message!"
          )
        end
      end
    end
  end
end
