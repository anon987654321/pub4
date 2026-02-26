# frozen_string_literal: true

require "English"
require "shellwords"

module MASTER
  class Server
    # Handlers - Route handler methods for web server
    module Handlers
      def handle_poll(queue)
        text = begin; queue.pop(true) unless queue.empty?; rescue ThreadError; nil; end
        body = {
          text: text, tier: LLM.tier,
          budget: "unlimited", version: VERSION
        }.to_json
        [200, { CT_HEADER => JSON_TYPE }, [body]]
      end

      def handle_sse(queue)
        body = Enumerator.new do |y|
          y << "retry: 1000\n\n"
          loop do
            text = begin; queue.pop(true) unless queue.empty?; rescue ThreadError; nil; end
            if text
              data = { text: text, tier: LLM.tier }.to_json
              y << "data: #{data}\n\n"
            else
              y << ": keep-alive\n\n"
            end
            sleep 0.3
          end
        end
        [200, {
          CT_HEADER          => "text/event-stream",
          "Cache-Control"    => "no-cache",
          "X-Accel-Buffering" => "no",
        }, body]
      end

      def handle_chat(env, pipeline, queue)
        body = env["rack.input"].read
        data = begin
          JSON.parse(body, symbolize_names: true)
        rescue StandardError
          {}
        end
        message = data[:message].to_s.strip

        if message.empty?
          [400, { CT_HEADER => JSON_TYPE }, ['{"error":"no message"}']]
        else
          image = data[:image]  # { data: base64, mime: "image/...", name: "file.jpg" }
          input = { text: message }
          if image && image[:data] && !image[:data].empty?
            input[:image_data] = image[:data]
            input[:image_mime] = image[:mime].to_s
            input[:image_name] = image[:name].to_s
          end
          Thread.new do
            result = pipeline.call(input)
            output = result.ok? ? result.value[:rendered] : "Error: #{result.error}"
            queue.push(output)
          rescue StandardError => err
            queue.push("Error: #{err.message}")
          end
          [200, { CT_HEADER => JSON_TYPE }, ['{"status":"processing"}']]
        end
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
        if result.respond_to?(:ok?) && result.ok? && result.value[:audio]
          ct = result.value[:content_type] || "audio/mpeg"
          [200, { CT_HEADER => ct }, [result.value[:audio]]]
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
