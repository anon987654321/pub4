# frozen_string_literal: true

module MASTER
  class Server
    # Handlers - Route handler methods for web server
    module Handlers
      def handle_poll(queue)
        text = begin; queue.pop(true) unless queue.empty?; rescue ThreadError; nil; end
        body = {
          text: text, tier: LLM.tier,
          budget: LLM.budget_remaining, version: VERSION,
        }.to_json
        [200, { CT_HEADER => JSON_TYPE }, [body]]
      end

      def handle_chat(env, pipeline, queue)
        body = env["rack.input"].read
        data = JSON.parse(body, symbolize_names: true) rescue {}
        message = data[:message].to_s.strip

        if message.empty?
          [400, { CT_HEADER => JSON_TYPE }, ['{"error":"no message"}']]
        else
          Thread.new do
            result = pipeline.call({ text: message })
            output = result.ok? ? result.value[:rendered] : "Error: #{result.error}"
            queue.push(output)
          rescue StandardError => e
            queue.push("Error: #{e.message}")
          end
          [200, { CT_HEADER => JSON_TYPE }, ['{"status":"processing"}']]
        end
      end

      def handle_metrics
        metrics = {
          version: VERSION, tier: LLM.tier,
          budget_remaining: LLM.budget_remaining,
          models: LLM.models.count,
          llm_provider: "openrouter",
          media_provider: "replicate",
          tts: defined?(Audio) ? Audio.engine_status : "unavailable",
          self: defined?(SelfAwareness) ? SelfAwareness.summary : "unavailable",
        }.to_json
        [200, { CT_HEADER => JSON_TYPE }, [metrics]]
      end

      def handle_tts(env)
        body = env["rack.input"].read
        data = JSON.parse(body, symbolize_names: true) rescue {}
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
    end
  end
end
