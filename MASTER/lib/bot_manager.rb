# frozen_string_literal: true

module MASTER
  # BotManager orchestrates multiple platform adapters
  # Routes messages between platforms and CLI
  class BotManager
    attr_reader :platforms, :event_bus, :cli

    def initialize(cli, event_bus, config = {})
      @cli = cli
      @event_bus = event_bus
      @config = config
      @platforms = {}
      @running = false
      @message_queue = Queue.new
      @mutex = Mutex.new
      
      setup_event_handlers
    end

    # Register a platform adapter
    def register_platform(name, adapter)
      @mutex.synchronize do
        @platforms[name] = adapter
      end
    end

    # Start all enabled platforms
    def start_all
      return if @running
      @running = true

      @platforms.each do |name, adapter|
        begin
          adapter.start
          puts "#{MASTER::CLI::ICON_OK} #{name} started"
        rescue => e
          puts "#{MASTER::CLI::ICON_ERR} #{name} failed: #{e.message}"
          MASTER::Audit.log(
            command: "start #{name}",
            type: :bot_startup,
            status: :error,
            output_length: 0,
            session_id: 'bot_manager'
          )
        end
      end

      # Start message processor thread
      start_message_processor
      
      emit(:bot_manager_started, { platforms: @platforms.keys })
    end

    # Stop all platforms
    def stop_all
      @running = false
      
      @platforms.each do |name, adapter|
        begin
          adapter.stop
          puts "#{MASTER::CLI::ICON_OK} #{name} stopped"
        rescue => e
          puts "#{MASTER::CLI::ICON_WARN} #{name} stop error: #{e.message}"
        end
      end
      
      emit(:bot_manager_stopped, {})
    end

    # Send message to specific platform
    def send_to_platform(platform_name, channel_id, text)
      adapter = @platforms[platform_name.to_sym]
      raise "Platform #{platform_name} not found" unless adapter
      
      adapter.handle_outgoing(channel_id, text)
    end

    # Broadcast message to all platforms
    def broadcast(text, exclude: [])
      @platforms.each do |name, adapter|
        next if exclude.include?(name)
        
        # Get default channel from config
        channels = @config.dig(name, :default_channels) || []
        channels.each do |channel_id|
          begin
            send_to_platform(name, channel_id, text)
          rescue => e
            emit(:broadcast_error, {
              platform: name,
              channel: channel_id,
              error: e.message
            })
          end
        end
      end
    end

    # Get platform statistics
    def stats
      {
        platforms: @platforms.keys,
        running: @running,
        message_queue_size: @message_queue.size,
        event_count: @event_bus.event_count
      }
    end

    private

    def setup_event_handlers
      # Subscribe to platform events
      @event_bus.subscribe(:message_received) do |event|
        handle_incoming_message(event)
      end

      @event_bus.subscribe(:platform_error) do |event|
        handle_platform_error(event)
      end

      @event_bus.subscribe(:message_failed) do |event|
        handle_message_failure(event)
      end

      @event_bus.subscribe(:rate_limited) do |event|
        handle_rate_limit(event)
      end
    end

    def handle_incoming_message(event)
      data = event.data
      
      # Log the incoming message
      MASTER::Audit.log(
        command: "incoming from #{data[:platform]}/#{data[:channel_id]}",
        type: :bot_incoming,
        status: :success,
        output_length: data[:text].length,
        session_id: 'bot_manager'
      )
      
      # Queue message for processing
      @message_queue.push({
        platform: data[:platform],
        channel_id: data[:channel_id],
        user_id: data[:user_id],
        text: data[:text],
        timestamp: data[:timestamp]
      })
    end

    def handle_platform_error(event)
      data = event.data
      puts "#{MASTER::CLI::ICON_ERR} #{data[:platform]} error: #{data[:error]}"
      
      MASTER::Audit.log(
        command: "platform_error #{data[:platform]}",
        type: :bot_error,
        status: :error,
        output_length: 0,
        session_id: 'bot_manager'
      )
    end

    def handle_message_failure(event)
      data = event.data
      
      # Implement dead letter queue for failed messages
      dead_letter_file = File.join(MASTER::Paths.var, 'bot_dead_letter.log')
      File.open(dead_letter_file, 'a') do |f|
        f.puts({
          timestamp: Time.now.to_i,
          platform: data[:platform],
          channel: data[:channel_id],
          error: data[:error]
        }.to_json)
      end
    end

    def handle_rate_limit(event)
      data = event.data
      puts "#{MASTER::CLI::ICON_WARN} #{data[:platform]} rate limited, reset at #{data[:reset_at]}"
    end

    def start_message_processor
      Thread.new do
        while @running
          begin
            # Wait for message with timeout
            message = @message_queue.pop(true)
            process_message(message)
          rescue ThreadError
            # Queue empty, sleep briefly
            sleep 0.1
          rescue => e
            puts "#{MASTER::CLI::ICON_ERR} Message processor error: #{e.message}"
          end
        end
      end
    end

    def process_message(message)
      # Format input for CLI
      input = message[:text]
      
      # Process through CLI
      result = @cli.process_input(input)
      
      return unless result
      
      # Send response back to the originating platform
      response_text = format_response(result)
      
      send_to_platform(
        message[:platform],
        message[:channel_id],
        response_text
      )
    rescue => e
      # Send error message back
      error_text = "#{MASTER::CLI::ICON_ERR} Error: #{e.message}"
      
      begin
        send_to_platform(
          message[:platform],
          message[:channel_id],
          error_text
        )
      rescue
        # Give up if we can't send error
      end
    end

    def format_response(result)
      # Format CLI response for social media platforms
      # Remove excessive whitespace and ANSI codes
      text = result.to_s
      text = text.gsub(/\e\[[0-9;]*m/, '') # Remove ANSI codes
      text = text.strip
      
      # Truncate if too long (most platforms have limits)
      max_length = @config.dig(:limits, :max_message_length) || 2000
      if text.length > max_length
        text = text[0...max_length - 3] + '...'
      end
      
      text
    end

    def emit(event_type, data)
      @event_bus.publish(event_type, data)
    end
  end
end
