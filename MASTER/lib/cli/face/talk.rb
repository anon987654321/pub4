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
          said = ask(session)
          session.add_message(role: :assistant, content: said)
          said
        end

        def ask(session)
          key = gemini_key
          return "I have no speech key, so I cannot answer." unless key

          uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent?key=#{key}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = WAIT_S
          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req.body = body(session).to_json
          res = http.request(req)
          text = JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text").to_s.strip
          return "I heard you, and the reply came back empty." if text.empty?

          text
        rescue Net::OpenTimeout, Net::ReadTimeout
          "I heard you. The reply took too long."
        rescue StandardError => e
          "I heard you, and the reply failed: #{e.message}"
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
