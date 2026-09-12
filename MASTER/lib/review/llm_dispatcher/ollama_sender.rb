# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Review
    class LLMDispatcher
      # The local tier, over Ollama's own HTTP API.
      #
      # models.yml has declared `ollama:` ids since the tier was written and
      # ModelRouter learned to exclude them when OLLAMA_BASE_URL is unset. The
      # half nobody had built is this one, and provider_availability.rb says so
      # in a comment: with no branch here, an id that *passed* the gate fell
      # through to RubyLLM, which handed `ollama:llama3:latest` to OpenRouter and
      # got an error back. So enabling the tier was the way to break it.
      #
      # Not through RubyLLM, deliberately. RubyLLM's provider list is a registry
      # of paid endpoints with prices and capability flags; a local daemon has
      # neither, and /api/chat is one POST returning one JSON object. The whole
      # client is the two methods below.
      module OllamaSender
        DEFAULT_BASE_URL = "http://localhost:11434"
        CHAT_PATH = "/api/chat"
        OPEN_TIMEOUT_S = 5
        READ_TIMEOUT_S = 300

        private

        def ollama_model?(model_id) = model_id.to_s.start_with?("ollama:", "ollama/")

        # Local inference is free, so there is no cost to record — but the token
        # counts still are, because a run's token total is how the session
        # reports what it did and a local model that answered silently would
        # read as a model that never ran.
        def send_ollama(selected_model, messages, sys:, stream: false, &blk)
          model = selected_model.to_s.sub(/\Aollama[:\/]/, "")
          body = { model:, messages: ollama_messages(messages, sys), stream: }
          response = ollama_post(body, stream:, &blk)
          return response unless response.ok?

          text, tokens = response.value!
          record_local_usage(selected_model, tokens)
          Result.ok(text)
        end

        def ollama_messages(messages, sys)
          system = sys.to_s
          rows = messages.map { |entry| { role: entry[:role].to_s, content: entry[:content].to_s } }
          system.empty? ? rows : [{ role: "system", content: system }] + rows
        end

        def ollama_base_url
          url = ENV["OLLAMA_BASE_URL"].to_s.strip
          url.empty? ? DEFAULT_BASE_URL : url.chomp("/")
        end

        # Every failure names itself. "Ollama is enabled but unreachable" and
        # "Ollama answered and has no such model" are different operator actions,
        # and a tier that reports both as a generic provider error sends the
        # reader to the wrong one.
        def ollama_post(body, stream:, &blk)
          uri = ollama_uri
          request = ollama_request(uri, body)
          outcome = nil
          ollama_http(uri).start do |session|
            session.request(request) do |response|
              outcome = ollama_response(response, body[:model], stream:, &blk)
            end
          end
          outcome
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          Result.err("ollama unreachable at #{ollama_base_url}: #{e.message}", category: :provider_error)
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          Result.err("ollama timed out at #{ollama_base_url}: #{e.message}", category: :timeout)
        end

        def ollama_uri
          URI.join("#{ollama_base_url}/", CHAT_PATH.delete_prefix("/"))
        end

        def ollama_http(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT_S
          http.read_timeout = READ_TIMEOUT_S
          http
        end

        def ollama_request(uri, body)
          request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
          request.body = JSON.generate(body)
          request
        end

        def ollama_response(response, model, stream:, &blk)
          return ollama_http_error(response, model) unless response.is_a?(Net::HTTPSuccess)

          stream ? read_ollama_stream(response, &blk) : read_ollama_reply(response)
        end

        def ollama_http_error(response, model)
          detail = response.body.to_s[0, 300]
          return Result.err("ollama has no model #{model}: #{detail}", category: :provider_error) if response.code == "404"

          Result.err("ollama #{response.code}: #{detail}", category: :provider_error)
        end

        # One JSON object, with the token counts Ollama reports for the run.
        def read_ollama_reply(response)
          parsed = JSON.parse(response.body.to_s)
          Result.ok([parsed.dig("message", "content").to_s, ollama_tokens(parsed)])
        rescue JSON::ParserError => e
          Result.err("ollama returned unparseable JSON: #{e.message}", category: :llm_failure)
        end

        # NDJSON: one object per chunk, the last carrying done and the counts.
        def read_ollama_stream(response)
          text = +""
          tokens = 0
          response.read_body do |segment|
            segment.each_line do |line|
              next if line.strip.empty?

              chunk = JSON.parse(line)
              piece = chunk.dig("message", "content").to_s
              unless piece.empty?
                text << piece
                yield piece if block_given?
              end
              tokens = ollama_tokens(chunk) if chunk["done"]
            end
          end
          Result.ok([text, tokens])
        rescue JSON::ParserError => e
          Result.err("ollama stream returned unparseable JSON: #{e.message}", category: :llm_failure)
        end

        def ollama_tokens(parsed)
          parsed["prompt_eval_count"].to_i + parsed["eval_count"].to_i
        end

        def record_local_usage(model, tokens)
          return unless @session && tokens.positive?

          @session.record_cost(0.0, model:, tokens:)
          publish_llm_cost(model:, cost: 0.0, tokens:, tokens_in: 0, tokens_out: tokens)
        rescue StandardError => e
          @bus&.publish("cost:record_error", error: e.message)
        end
      end
    end
  end
end
