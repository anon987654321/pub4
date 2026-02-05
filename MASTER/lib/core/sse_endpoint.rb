# frozen_string_literal: true

require 'async'

module MASTER
  # SSE (Server-Sent Events) endpoint for real-time orb updates
  class SSEEndpoint
    attr_reader :clients
    
    def initialize
      @clients = []
      @mutex = Mutex.new
    end
    
    # Register new client
    def register(client)
      @mutex.synchronize do
        @clients << client
        puts "SSE client connected (#{@clients.size} total)" if ENV['DEBUG']
      end
    end
    
    # Unregister client
    def unregister(client)
      @mutex.synchronize do
        @clients.delete(client)
        puts "SSE client disconnected (#{@clients.size} total)" if ENV['DEBUG']
      end
    end
    
    # Broadcast message to all clients
    def broadcast(event_type, data)
      message = format_sse(event_type, data)
      
      @mutex.synchronize do
        @clients.each do |client|
          begin
            client.write(message)
            client.flush
          rescue => e
            puts "Failed to send to client: #{e.message}" if ENV['DEBUG']
            @clients.delete(client)
          end
        end
      end
    end
    
    # Send orb update
    def send_orb_update(mood:, color:, animation:, metadata: {})
      data = {
        mood: mood,
        color: color,
        animation: animation,
        timestamp: Time.now.to_i
      }.merge(metadata)
      
      broadcast('orb', data)
    end
    
    # Send token stream
    def send_token(token, metadata: {})
      data = {
        token: token,
        timestamp: Time.now.to_i
      }.merge(metadata)
      
      broadcast('token', data)
    end
    
    # Send status update
    def send_status(status, message = nil)
      data = {
        status: status,
        message: message,
        timestamp: Time.now.to_i
      }
      
      broadcast('status', data)
    end
    
    # Send completion signal
    def send_complete(result = {})
      data = {
        complete: true,
        timestamp: Time.now.to_i
      }.merge(result)
      
      broadcast('complete', data)
    end
    
    # Send error
    def send_error(error, details = nil)
      data = {
        error: error,
        details: details,
        timestamp: Time.now.to_i
      }
      
      broadcast('error', data)
    end
    
    # Keep connection alive
    def send_heartbeat
      @mutex.synchronize do
        @clients.each do |client|
          begin
            client.write(": heartbeat\n\n")
            client.flush
          rescue => e
            @clients.delete(client)
          end
        end
      end
    end
    
    # Start heartbeat task
    def start_heartbeat(interval: 30)
      Async do |task|
        loop do
          task.sleep(interval)
          send_heartbeat
        end
      end
    end
    
    # Get client count
    def client_count
      @mutex.synchronize { @clients.size }
    end
    
    # Close all connections
    def close_all
      @mutex.synchronize do
        @clients.each do |client|
          begin
            client.close
          rescue StandardError
            # Ignore errors on close
          end
        end
        @clients.clear
      end
    end
    
    private
    
    # Format message as SSE
    def format_sse(event_type, data)
      json_data = data.is_a?(String) ? data : JSON.generate(data)
      "event: #{event_type}\ndata: #{json_data}\n\n"
    end
  end
end
