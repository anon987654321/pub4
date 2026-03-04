# frozen_string_literal: true

require "English"
require "shellwords"

module MASTER
  class Server
    # Handlers - Route handler methods for web server
    module Handlers
      def handle_poll(queue)
        raw = begin; queue.pop(true) unless queue.empty?; rescue ThreadError; nil; end
        body =
          if raw
            begin
              JSON.parse(raw)  # already JSON from handle_chat
              raw
            rescue JSON::ParserError
              { text: raw, tier: LLM.tier, budget: "unlimited", version: VERSION }.to_json
            end
          else
            { text: nil, tier: LLM.tier, budget: "unlimited", version: VERSION }.to_json
          end
        [200, { CT_HEADER => JSON_TYPE }, [body]]
      end

      def handle_chat(env, pipeline, queue, sessions = {}, lock = Mutex.new)
        body = env["rack.input"].read
        data = begin
          JSON.parse(body, symbolize_names: true)
        rescue StandardError
          {}
        end
        message    = data[:message].to_s.strip
        session_id = data[:session_id].to_s.strip
        session_id = SecureRandom.hex(16) if session_id.empty?

        return [400, { CT_HEADER => JSON_TYPE }, ['{"error":"no message"}']] if message.empty?

        web_session = lock.synchronize { sessions[session_id] ||= { pipeline: pipeline, session: Session.new } }
        session     = web_session[:session]
        pipeline    = web_session[:pipeline]

        Thread.new do
          session.add_user(message)
          output = dispatch_message(message, pipeline)
          session.add_assistant(output) if output && !output.empty?
          queue.push({ text: output, session_id: session_id, tier: LLM.tier }.to_json)
        rescue StandardError => e
          queue.push({ text: "Error: #{e.message}", session_id: session_id }.to_json)
        end

        [200, { CT_HEADER => JSON_TYPE }, [{ status: "processing", session_id: session_id }.to_json]]
      end

      def handle_metrics
        dirty_count = git_dirty_count
        metrics = {
          version: VERSION, tier: LLM.tier,
          budget_remaining: "unlimited",
          models: LLM.models.count,
          llm_provider: "openrouter",
          media_provider: "replicate",
          tts: defined?(Audio) ? Audio.engine_status : "unavailable",
          self: defined?(SelfAwareness) ? SelfAwareness.summary : "unavailable",
          repo_dirty_count: dirty_count,
          repo_state: dirty_count.zero? ? "clean" : "dirty"
        }.to_json
        [200, { CT_HEADER => JSON_TYPE }, [metrics]]
      end

      def handle_tts(env)
        body = env["rack.input"].read
        data = begin
          JSON.parse(body, symbolize_names: true)
        rescue StandardError
          {}
        end
        text = data[:text].to_s.strip

        return [400, { CT_HEADER => JSON_TYPE }, ['{"error":"no text provided"}']] if text.empty?
        unless defined?(Speech) && Speech.respond_to?(:speak)
          return [501, { CT_HEADER => JSON_TYPE }, ['{"error":"TTS not available"}']]
        end

        result = Speech.speak(text, play: false)
        if result.respond_to?(:ok?) && result.ok?
          audio_data = result.value[:audio] || result.value[:data]
          [200, { CT_HEADER => "audio/mpeg" }, [audio_data]]
        else
          error = result.respond_to?(:error) ? result.error : "TTS failed"
          [500, { CT_HEADER => JSON_TYPE }, [{ error: error }.to_json]]
        end
      end

      def handle_tts_stream(env)
        text = Rack::Utils.parse_query(env["QUERY_STRING"])["text"]
        return [400, {}, ["Missing text"]] unless text

        [501, { CT_HEADER => TEXT_TYPE }, ["TTS streaming not implemented"]]
      end

      def serve_static_file(path)
        clean_path = File.basename(path)
        view_path = File.expand_path(clean_path, VIEWS_DIR)

        if view_path.start_with?(VIEWS_DIR) && File.exist?(view_path) && File.file?(view_path)
          ext = File.extname(path)
          type = { ".html" => HTML_TYPE, ".js" => "application/javascript", ".css" => "text/css" }[ext] || TEXT_TYPE
          [200, { CT_HEADER => type }, [File.read(view_path)]]
        else
          [404, { CT_HEADER => TEXT_TYPE }, ["Not found"]]
        end
      end

      private

      def dispatch_message(message, pipeline)
        if defined?(Commands)
          cmd = Commands.dispatch(message, pipeline: pipeline)
          if cmd == :exit
            "Goodbye."
          elsif cmd.respond_to?(:ok?)
            cmd.ok? ? (cmd.value[:rendered] || cmd.value[:response] || "") : "! #{cmd.failure}"
          else
            result = pipeline.call({ text: message })
            result.ok? ? (result.value[:rendered] || result.value[:response] || "") : "! #{result.failure}"
          end
        else
          result = pipeline.call({ text: message })
          result.ok? ? (result.value[:rendered] || result.value[:response] || "") : "! #{result.failure}"
        end
      end

      def git_dirty_count
        root = defined?(MASTER) && MASTER.respond_to?(:root) ? MASTER.root : Dir.pwd
        output = `git -C #{Shellwords.escape(root)} status --porcelain 2>/dev/null`
        return 0 unless $CHILD_STATUS.success?

        output.lines.size
      rescue StandardError
        0
      end
    end
  end
end
