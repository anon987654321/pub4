# frozen_string_literal: true

require "json"
require "net/http"

module Master
  module CLI
    module Face
      # A spoken turn. The full agent sends the code index and then waits on
      # agy for minutes, which is a silence in a face. This keeps the session
      # transcript — the last turns, not one line — and asks for a short reply.
      module Talk
        MODEL = "gemini-2.5-flash"
        TURNS = 20
        CLIP = 1_500
        WAIT_S = 20

        module_function

        def for_session(session)
          lambda do |text|
            reply(session, text)
          end
        end

        def reply(session, text)
          session.add_message(role: :user, content: text)
          result = ask(session)
          return result if result.err?

          session.add_message(role: :assistant, content: result.value!)
          result
        end

        def ask(session, api_key: nil, http_class: Net::HTTP)
          key = api_key || gemini_key
          return Master::Result.err("talk0: GEMINI_API_KEY missing", category: :validation) unless key

          uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent?key=#{key}")
          http = http_class.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = WAIT_S
          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req.body = body(session).to_json
          parse_response(http.request(req))
        rescue Net::OpenTimeout, Net::ReadTimeout
          Master::Result.err("talk0: request timed out", category: :timeout)
        rescue StandardError => e
          Master::Result.err("talk0: request failed — #{e.class}: #{e.message}", category: :infrastructure)
        end

        def parse_response(response)
          status = response.code.to_i
          payload = JSON.parse(response.body.to_s)
          unless status.between?(200, 299)
            detail = payload.dig("error", "message").to_s.strip
            detail = "HTTP #{status}" if detail.empty?
            return Master::Result.err("talk0: #{detail}", category: :provider_error)
          end

          text = payload.dig("candidates", 0, "content", "parts", 0, "text").to_s.strip
          return Master::Result.ok(text) unless text.empty?

          reason = payload.dig("promptFeedback", "blockReason").to_s.strip
          reason = payload.dig("candidates", 0, "finishReason").to_s.strip if reason.empty?
          detail = reason.empty? ? "empty response" : "empty response (#{reason.downcase})"
          Master::Result.err("talk0: #{detail}", category: :provider_error)
        rescue JSON::ParserError => e
          Master::Result.err("talk0: invalid JSON — #{e.message}", category: :provider_error)
        end

        def body(session)
          {
            systemInstruction: { parts: [{ text: "You are MASTER, in conversation. Answer in one to three spoken sentences. Remember what was already said in this transcript. Do not describe how you are built." }] },
            contents: transcript(session),
            generationConfig: { thinkingConfig: { thinkingBudget: 0 } },
          }
        end

        def transcript(session)
          rows = Array(session.messages).last(TURNS)
          rows.filter_map do |msg|
            role = (msg[:role] || msg["role"]).to_s
            content = (msg[:content] || msg["content"]).to_s.strip
            next if content.empty?

            { role: role == "assistant" ? "model" : "user", parts: [{ text: content[0, CLIP] }] }
          end
        end

        def gemini_key
          return ENV["GEMINI_API_KEY"] unless ENV["GEMINI_API_KEY"].to_s.empty?

          path = File.expand_path("~/.config/master/env")
          return unless File.file?(path)

          File.foreach(path) do |line|
            name, value = line.strip.sub(/\Aexport\s+/, "").split("=", 2)
            return value.to_s.delete(%("')) if name == "GEMINI_API_KEY"
          end
          nil
        end
      end
    end
  end
end
