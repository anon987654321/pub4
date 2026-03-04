# frozen_string_literal: true

module MASTER
  class Server
    # WebSocket - WebSocket connection handler
    module WebSocket
      def handle_websocket(env, pipeline, sessions = {}, lock = Mutex.new)
        begin
          require "async"
          require "async/websocket/adapters/rack"
        rescue LoadError
          Logging.warn("async-websocket not available", subsystem: "WebSocket")
          return [501, { CT_HEADER => TEXT_TYPE }, ["WebSocket not available"]]
        end

        query      = Rack::Utils.parse_query(env["QUERY_STRING"] || "")
        session_id = query["session_id"] || SecureRandom.hex(16)
        web_session = lock.synchronize { sessions[session_id] ||= { pipeline: pipeline, session: Session.new } }
        session     = web_session[:session]
        pipeline    = web_session[:pipeline]

        Async::WebSocket::Adapters::Rack.open(env, protocols: ["chat"]) do |connection|
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

                session.add_user(user_message)
                response_text = dispatch_message(user_message, pipeline)
                session.add_assistant(response_text) if response_text && !response_text.empty?

                connection.write({ type: "chunk", text: response_text }.to_json)
                connection.flush
                connection.write({ type: "done", meta: { tier: LLM.tier, budget: "unlimited" } }.to_json)
              else
                connection.write({ type: "error", message: "Unknown message type" }.to_json)
              end
              connection.flush
            rescue JSON::ParserError
              connection.write({ type: "error", message: "Invalid JSON" }.to_json)
              connection.flush
            rescue StandardError => e
              Logging.warn("Error: #{e.message}", subsystem: "WebSocket")
              connection.write({ type: "error", message: e.message }.to_json)
              connection.flush
            end
          end
        rescue StandardError => e
          Logging.warn("Connection error: #{e.message}", subsystem: "WebSocket")
        end

        nil
      end
    end
  end
end
