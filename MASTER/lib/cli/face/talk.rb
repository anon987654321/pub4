# frozen_string_literal: true

require "json"
require "net/http"

module Master
  module CLI
    module Face
      # A spoken turn. The full agent sends the code index and then waits on
      # agy for minutes, which is a silence in a face. This keeps the session
      # transcript — the last turns, not one line — and asks for a short reply.
      #
      # Gemini answers first when a key is set. Its free tier allows twenty
      # requests a day, so any failure there walks on to one short call on a
      # lane the router reports live, and only then to one sentence saying what
      # would give the face a voice. The whole turn stays inside WAIT_S.
      module Talk
        MODEL = "gemini-2.5-flash"
        TURNS = 20
        CLIP = 1_500
        WAIT_S = 20
        LANE_S = 12
        LANES = 3
        SYSTEM = "You are MASTER, in conversation. Answer in one to three spoken sentences. " \
                 "Remember what was already said in this transcript. Do not describe how you are built."
        SETUP = "set GEMINI_API_KEY or OPENROUTER_API_KEY in ~/.config/master/env, sign in with `claude`, " \
                "or start ollama"
        # agy is the minutes-long lane the face left; web-chat drives a browser;
        # replicate starts cold; a bare gemini id spends the key just refused;
        # opus is the slowest claude.
        SLOW = /\A(?:agy(?::|\z)|web-chat:|replicate:|gemini)|opus/

        module_function

        def for_session(session, container: Fiber[:master_cli_container])
          agent = container && container[:agent]
          router = agent.model_router if agent.respond_to?(:model_router)
          ->(text) { reply(session, text, router:, agent:) }
        end

        def reply(session, text, **lanes)
          session.add_message(role: :user, content: text)
          result = ask(session, **lanes)
          return result if result.err?

          session.add_message(role: :assistant, content: result.value!)
          result
        end

        def ask(session, api_key: gemini_key, http_class: Net::HTTP, router: nil, agent: nil)
          deadline = clock + WAIT_S
          gemini = ask_gemini(session, api_key, http_class) unless api_key.to_s.empty?
          return gemini if gemini&.ok?

          routed(session, router, agent, deadline, gemini)
        end

        def ask_gemini(session, key, http_class)
          uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent?key=#{key}")
          http = http_class.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = LANE_S
          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req.body = body(session).to_json
          parse_response(http.request(req))
        rescue Net::OpenTimeout, Net::ReadTimeout
          Master::Result.err("talk0: request timed out", category: :timeout)
        rescue StandardError => e
          Master::Result.err("talk0: request failed — #{e.class}: #{e.message}", category: :infrastructure)
        end

        # One lane at a time, each bounded by what is left of the turn.
        def routed(session, router, agent, deadline, gemini)
          failures = gemini ? ["gemini: #{gemini.message.delete_prefix('talk0: ')}"] : []
          models = agent.respond_to?(:ask_once) ? live_lanes(router) : []
          return Master::Result.err(nothing_live(failures), category: :no_api_key) if models.empty?

          prompt = spoken_prompt(session)
          models.first(LANES).each do |model|
            left = deadline - clock
            break unless left.positive?

            result = ask_lane(agent, model, prompt, [left, LANE_S].min)
            return result if result.ok?

            failures << "#{model}: #{result.message}"
          end
          Master::Result.err("talk0: no lane answered — #{failures.join('; ')}", category: :provider_error)
        end

        def nothing_live(failures)
          said = failures.empty? ? "no model is set up" : "#{failures.join('; ')}, and no other lane is live"
          "talk0: #{said} — #{SETUP}"
        end

        # The chitchat chain, which the router already filtered to reachable
        # models and away from ones that just failed, less the slow lanes and
        # any free model past its daily quota.
        def live_lanes(router)
          return [] unless router.respond_to?(:fallback_chain)

          Array(router.fallback_chain(task_type: :chitchat)).uniq.reject do |id|
            SLOW.match?(id.to_s) || command_lane?(router, id) || Master::Io::ModelQuota.over_quota?(id)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Face::Talk.live_lanes")
          []
        end

        # codex and grok answer through a subprocess that can take minutes.
        def command_lane?(router, id) = router.respond_to?(:cli_lane_model?) && router.cli_lane_model?(id)

        # A lane past its time is left to finish on its own, not killed: killing
        # the thread closes the pipes under the dispatcher's reader threads,
        # which print a backtrace over the face.
        def ask_lane(agent, model, prompt, seconds)
          worker = Thread.new do
            Thread.current.report_on_exception = false
            Fiber[:master_no_tools] = true
            agent.ask_once(prompt, system: SYSTEM, law: false, model:, failover: false)
          end
          return Master::Result.err("timed out after #{seconds.round}s", category: :timeout) unless worker.join(seconds)

          text = worker.value.to_s.strip
          return Master::Result.err("empty reply", category: :provider_error) if text.empty?

          Master::Result.ok(text).with_model(model)
        rescue StandardError => e
          Master::Result.err(e.message.to_s.lines.first.to_s.strip, category: :provider_error)
        end

        # ask_once takes one prompt, so the transcript travels as its text.
        def spoken_prompt(session)
          transcript(session).map { |row| "#{row[:role] == 'model' ? 'MASTER' : 'user'}: #{row[:parts][0][:text]}" }
                             .join("\n\n")
        end

        def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
            systemInstruction: { parts: [{ text: SYSTEM }] },
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
