# frozen_string_literal: true

module MASTER
  class Server
    # WebSocket - WebSocket connection handler
    module WebSocket
      def handle_websocket(env, pipeline)
        # Try to load async-websocket, return 501 if not available
        begin
          require "async"
          require "async/websocket/adapters/rack"
        rescue LoadError
          Logging.warn("WebSocket", "async-websocket not available")
          return [501, { CT_HEADER => TEXT_TYPE }, ["WebSocket not available"]]
        end

        Async::WebSocket::Adapters::Rack.open(env, protocols: ["chat"]) do |connection|
          # WebSocket connection established
          while (message = connection.read)
            begin
              data = JSON.parse(message, symbolize_names: true)

              if data[:type] == "chat"
                user_message = data[:message].to_s.strip

                if user_message.empty?
                  connection.write({ type: "error", message: "Empty message" }.to_json)
                  connection.flush
                  next
                end

                # Process message through pipeline
                result = pipeline.call({ text: user_message })

                if result.ok?
                  response_text = result.value[:rendered] || result.value[:text] || ""

                  # Stream response in chunks (simulate streaming by sending full response)
                  # In a real implementation, you'd hook into the LLM's streaming API
                  connection.write({ type: "chunk", text: response_text }.to_json)
                  connection.flush

                  # Send done message with metadata
                  meta = {
                    tier: LLM.tier,
                    budget: LLM.budget_remaining,
                    tokens: result.value[:tokens] || 0,
                    cost: result.value[:cost] || 0.0,
                  }
                  connection.write({ type: "done", meta: meta }.to_json)
                  connection.flush
                else
                  connection.write({ type: "error", message: result.error }.to_json)
                  connection.flush
                end
              else
                connection.write({ type: "error", message: "Unknown message type" }.to_json)
                connection.flush
              end
            rescue JSON::ParserError
              connection.write({ type: "error", message: "Invalid JSON" }.to_json)
              connection.flush
            rescue StandardError => e
              Logging.warn("WebSocket", "Error: #{e.message}")
              connection.write({ type: "error", message: e.message }.to_json)
              connection.flush
            end
          end
        rescue StandardError => e
          Logging.warn("WebSocket", "Connection error: #{e.message}")
        end

        # Return nil to indicate WebSocket handled the request
        nil
      end
    end
  end
end
