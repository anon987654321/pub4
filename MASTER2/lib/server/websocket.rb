# frozen_string_literal: true

module MASTER
  class Server
    # WebSocket - WebSocket connection handler
    module WebSocket
      def handle_websocket(env, pipeline)
        begin
          require "async"
          require "async/websocket/adapters/rack"
        rescue LoadError
          Logging.warn("async-websocket not available", subsystem: "WebSocket")
          return [501, { CT_HEADER => TEXT_TYPE }, ["WebSocket not available"]]
        end

        Async::WebSocket::Adapters::Rack.open(env, protocols: ["chat"]) do |connection|
          while (message = connection.read)
            handle_ws_message(message, connection, pipeline)
          end
        rescue StandardError => err
          Logging.warn("Connection error: #{err.message}", subsystem: "WebSocket")
        end

        nil
      end

      private

      def handle_ws_message(message, connection, pipeline)
        data = JSON.parse(message, symbolize_names: true)

        unless data[:type] == "chat"
          connection.write({ type: "error", message: "Unknown message type" }.to_json)
          connection.flush
          return
        end

        user_message = data[:message].to_s.strip
        if user_message.empty?
          connection.write({ type: "error", message: "Empty message" }.to_json)
          connection.flush
          return
        end

        result = pipeline.call({ text: user_message })

        if result.ok?
          response_text = result.value[:rendered] || result.value[:text] || ""
          connection.write({ type: "chunk", text: response_text }.to_json)
          connection.flush
          meta = {
            tier: LLM.tier,
            budget: "unlimited",
            tokens: result.value[:tokens] || 0,
            cost: result.value[:cost] || 0.0,
          }
          connection.write({ type: "done", meta: meta }.to_json)
        else
          connection.write({ type: "error", message: result.error }.to_json)
        end
        connection.flush
      rescue JSON::ParserError
        connection.write({ type: "error", message: "Invalid JSON" }.to_json)
        connection.flush
      rescue Errno::EPIPE, IOError
        # Client disconnected — normal for WebSocket
      rescue StandardError => err
        Logging.warn("Error: #{err.message}", subsystem: "WebSocket")
        connection.write({ type: "error", message: err.message }.to_json)
        connection.flush
      end
    end
  end
end
