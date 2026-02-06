# frozen_string_literal: true

require_relative 'base'

module MASTER
  module Platforms
    # Slack integration using slack-ruby-client gem
    class Slack < Base
      def initialize(name, event_bus, token:, config: {})
        super
        @client = nil
        @web_client = nil
      end

      def send_message(channel_id, text)
        raise "Slack client not ready" unless @web_client
        
        retry_with_backoff do
          # Support blocks/attachments if configured
          options = {
            channel: channel_id,
            text: text
          }
          
          if config[:thread_ts]
            options[:thread_ts] = config[:thread_ts]
          end
          
          if config[:blocks]
            options[:blocks] = config[:blocks]
          end
          
          @web_client.chat_postMessage(**options)
        end
      end

      def listen(&handler)
        require 'slack-ruby-client'
        
        Slack.configure do |config|
          config.token = @token
        end
        
        @client = Slack::RealTime::Client.new
        @web_client = Slack::Web::Client.new(token: @token)
        
        @client.on :hello do
          emit(:slack_ready, { team: @client.team.name })
        end
        
        @client.on :message do |data|
          # Ignore bot messages
          next if data.subtype == 'bot_message'
          next unless data.text
          
          # Check whitelist if configured
          if config[:channel_whitelist] && !config[:channel_whitelist].empty?
            next unless config[:channel_whitelist].include?(data.channel)
          end
          
          # Check if bot was mentioned
          bot_user_id = @client.self.id
          mentioned = data.text.include?("<@#{bot_user_id}>")
          
          message_data = {
            channel_id: data.channel,
            user_id: data.user,
            text: data.text.gsub(/<@#{bot_user_id}>/, '').strip,
            username: get_username(data.user),
            thread_ts: data.thread_ts,
            mentioned: mentioned
          }
          
          handler.call(message_data) if handler
          handle_incoming(message_data)
        end
        
        @client.on :app_mention do |data|
          # Handle direct mentions
          bot_user_id = @client.self.id
          
          message_data = {
            channel_id: data.channel,
            user_id: data.user,
            text: data.text.gsub(/<@#{bot_user_id}>/, '').strip,
            username: get_username(data.user),
            thread_ts: data.thread_ts,
            mentioned: true
          }
          
          handler.call(message_data) if handler
          handle_incoming(message_data)
        end
        
        # Run in background thread
        Thread.new { @client.start! }
      end

      def verify_webhook(signature, body)
        # Slack uses HMAC-SHA256 signature verification
        return true unless config[:verify_signatures]
        
        signing_secret = config[:signing_secret]
        return false unless signing_secret
        
        require 'openssl'
        
        begin
          timestamp = signature[:timestamp]
          slack_signature = signature[:signature]
          
          basestring = "v0:#{timestamp}:#{body}"
          digest = OpenSSL::HMAC.hexdigest('SHA256', signing_secret, basestring)
          computed_signature = "v0=#{digest}"
          
          Rack::Utils.secure_compare(computed_signature, slack_signature)
        rescue => e
          emit(:verification_error, { platform: 'slack', error: e.message })
          false
        end
      end

      def on_stop
        @client&.stop!
        super
      end

      private

      def get_username(user_id)
        return 'unknown' unless @web_client
        
        begin
          response = @web_client.users_info(user: user_id)
          response.user.name
        rescue
          'unknown'
        end
      end
    end
  end
end
