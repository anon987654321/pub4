# frozen_string_literal: true

require_relative 'base'

module MASTER
  module Platforms
    # Twitter/X integration using twitter gem
    class Twitter < Base
      def initialize(name, event_bus, token:, config: {})
        super
        @client = nil
        @stream_client = nil
        @rate_limit_remaining = 0
        @rate_limit_reset = Time.now
      end

      def send_message(channel_id, text)
        raise "Twitter client not ready" unless @client
        
        # Check rate limits (Twitter is strict)
        check_rate_limits
        
        retry_with_backoff(max_attempts: 5, initial_delay: 2) do
          # channel_id can be a user_id for DM or "tweet" for public tweet
          if channel_id == 'tweet' || channel_id.nil?
            # Post a tweet
            @client.update(text)
          else
            # Send DM
            @client.create_direct_message(channel_id, text)
          end
        end
      rescue ::Twitter::Error::TooManyRequests => e
        # Handle rate limiting
        reset_time = Time.at(e.rate_limit.reset_at)
        sleep_time = [reset_time - Time.now, 0].max
        
        emit(:rate_limited, {
          platform: 'twitter',
          reset_at: reset_time,
          sleep_time: sleep_time
        })
        
        sleep sleep_time
        retry
      end

      def listen(&handler)
        require 'twitter'
        
        # Initialize REST client
        @client = ::Twitter::REST::Client.new do |config|
          config.consumer_key        = config[:consumer_key] || ENV['TWITTER_CONSUMER_KEY']
          config.consumer_secret     = config[:consumer_secret] || ENV['TWITTER_CONSUMER_SECRET']
          config.access_token        = @token
          config.access_token_secret = config[:access_token_secret] || ENV['TWITTER_ACCESS_SECRET']
        end
        
        emit(:twitter_ready, { username: @client.user.screen_name })
        
        # Use streaming API for real-time updates
        @stream_client = ::Twitter::Streaming::Client.new do |config|
          config.consumer_key        = config[:consumer_key] || ENV['TWITTER_CONSUMER_KEY']
          config.consumer_secret     = config[:consumer_secret] || ENV['TWITTER_CONSUMER_SECRET']
          config.access_token        = @token
          config.access_token_secret = config[:access_token_secret] || ENV['TWITTER_ACCESS_SECRET']
        end
        
        # Monitor mentions and DMs
        Thread.new do
          @stream_client.user do |object|
            case object
            when ::Twitter::Tweet
              # Ignore own tweets
              next if object.user.screen_name == @client.user.screen_name
              
              # Check if it's a mention
              mentioned = object.user_mentions.any? { |u| u.screen_name == @client.user.screen_name }
              next unless mentioned || config[:monitor_all]
              
              message_data = {
                channel_id: 'tweet',
                user_id: object.user.id.to_s,
                text: object.text,
                username: object.user.screen_name,
                tweet_id: object.id.to_s,
                in_reply_to: object.in_reply_to_status_id&.to_s
              }
              
              handler.call(message_data) if handler
              handle_incoming(message_data)
              
            when ::Twitter::DirectMessage
              # Handle DMs
              next if object.sender.screen_name == @client.user.screen_name
              
              message_data = {
                channel_id: object.sender.id.to_s,
                user_id: object.sender.id.to_s,
                text: object.text,
                username: object.sender.screen_name,
                is_dm: true
              }
              
              handler.call(message_data) if handler
              handle_incoming(message_data)
            end
          end
        end
      end

      def verify_webhook(signature, body)
        # Twitter uses HMAC-SHA256 signature verification
        return true unless config[:verify_signatures]
        
        consumer_secret = config[:consumer_secret] || ENV['TWITTER_CONSUMER_SECRET']
        return false unless consumer_secret
        
        require 'openssl'
        require 'base64'
        
        begin
          expected_signature = Base64.strict_encode64(
            OpenSSL::HMAC.digest('SHA256', consumer_secret, body)
          )
          
          Rack::Utils.secure_compare(signature, expected_signature)
        rescue => e
          emit(:verification_error, { platform: 'twitter', error: e.message })
          false
        end
      end

      def on_stop
        @stream_client&.disconnect if @stream_client
        super
      end

      private

      def check_rate_limits
        return if @rate_limit_remaining > 0 && Time.now < @rate_limit_reset
        
        # Check current rate limit status
        begin
          limits = @client.rate_limit_status
          dm_limits = limits.resources['direct_messages']['/direct_messages/events/new']
          
          @rate_limit_remaining = dm_limits.remaining
          @rate_limit_reset = Time.at(dm_limits.reset_at)
          
          if @rate_limit_remaining == 0
            sleep_time = [@rate_limit_reset - Time.now, 0].max
            emit(:rate_limited, {
              platform: 'twitter',
              reset_at: @rate_limit_reset,
              sleep_time: sleep_time
            })
            sleep sleep_time
          end
        rescue => e
          # If we can't check limits, proceed cautiously
          emit(:rate_limit_check_failed, { platform: 'twitter', error: e.message })
        end
      end
    end
  end
end
