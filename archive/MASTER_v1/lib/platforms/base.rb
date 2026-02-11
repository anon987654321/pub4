# frozen_string_literal: true

module MASTER
  module Platforms
    # Base adapter class for social media platform integrations
    # Inherits from Actors::Base for lifecycle management
    class Base < MASTER::Actors::Base
      attr_reader :platform_name, :token, :config

      def initialize(name, event_bus, token:, config: {})
        super(name, event_bus)
        @token = token
        @config = config
        @platform_name = self.class.name.split('::').last.downcase
      end

      # Send a message to a channel/chat
      # Must be implemented by subclasses
      def send_message(channel_id, text)
        raise NotImplementedError, "#{self.class} must implement #send_message"
      end

      # Start listening for incoming messages
      # Must be implemented by subclasses
      def listen(&handler)
        raise NotImplementedError, "#{self.class} must implement #listen"
      end

      # Verify webhook signature for incoming requests
      # Must be implemented by subclasses
      def verify_webhook(signature, body)
        raise NotImplementedError, "#{self.class} must implement #verify_webhook"
      end

      # Handle incoming message (called by listen)
      def handle_incoming(message_data)
        emit(:message_received, {
          platform: @platform_name,
          channel_id: message_data[:channel_id],
          user_id: message_data[:user_id],
          text: message_data[:text],
          timestamp: Time.now.to_i
        })
      rescue => e
        emit(:platform_error, {
          platform: @platform_name,
          error: e.message,
          backtrace: e.backtrace.first(5)
        })
      end

      # Handle outgoing message (called by bot manager)
      def handle_outgoing(channel_id, text)
        result = send_message(channel_id, text)
        
        emit(:message_sent, {
          platform: @platform_name,
          channel_id: channel_id,
          text: text,
          success: true,
          timestamp: Time.now.to_i
        })
        
        MASTER::Audit.log(
          command: "send_message to #{channel_id}",
          type: :bot_message,
          status: :success,
          output_length: text.length,
          session_id: @name
        )
        
        result
      rescue => e
        emit(:message_failed, {
          platform: @platform_name,
          channel_id: channel_id,
          error: e.message,
          timestamp: Time.now.to_i
        })
        
        MASTER::Audit.log(
          command: "send_message to #{channel_id}",
          type: :bot_message,
          status: :error,
          output_length: 0,
          session_id: @name
        )
        
        raise
      end

      # Override on_start to begin listening
      def on_start
        super
        emit(:platform_started, { platform: @platform_name })
      end

      # Override on_stop to cleanup
      def on_stop
        super
        emit(:platform_stopped, { platform: @platform_name })
      end

      # Retry logic with exponential backoff
      def retry_with_backoff(max_attempts: 3, initial_delay: 1, &block)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue => e
          if attempts < max_attempts
            delay = initial_delay * (2 ** (attempts - 1))
            sleep delay
            retry
          else
            raise
          end
        end
      end
    end
  end
end
