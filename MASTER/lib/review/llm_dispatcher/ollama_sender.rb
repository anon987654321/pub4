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
        CHARS_PER_TOKEN = 4
        CTX_STEP = 1024
        MIN_NUM_CTX = 4096
        REPLY_TOKENS = 2048
        # An effect object is a verb, a clause and its args. A cap this size
        # stops the repetition loop a constrained small model falls into on an
        # unbounded string.
        FORMAT_REPLY_TOKENS = 512

        private

        def ollama_model?(model_id) = model_id.to_s.start_with?("ollama:", "ollama/")

        # Local inference is free, so there is no cost to record — but the token
        # counts still are, because a run's token total is how the session
        # reports what it did and a local model that answered silently would
        # read as a model that never ran.
        def send_ollama(selected_model, messages, sys:, stream: false, temperature: nil, format: nil, &blk)
          model = selected_model.to_s.sub(/\Aollama[:\/]/, "")
          rows = ollama_messages(messages, sys)
          # Ollama Cloud models take no schema, so a :cloud id is asked plainly.
          format = nil if model.end_with?(":cloud")
          body = { model:, messages: rows, stream:, keep_alive: ollama_setting("keep_alive", "30m"),
                   options: ollama_options(rows, temperature:, format:) }
          body[:format] = format if format
          response = ollama_post(body, stream:, &blk)
          return response unless response.ok?

          text, tokens = response.value!
          record_local_usage(selected_model, tokens)
          Result.ok(text)
        end

        # Ollama gives an 8 GB machine a 4k window and drops what overflows it
        # without an error, so a fold transcript lost its goal and the model
        # answered a question nobody asked. The window is sized to the request,
        # up to models.yml ollama.max_num_ctx. A schema-bound reply decodes at
        # temperature 0, as Ollama's structured-output guide advises.
        def ollama_options(rows, temperature:, format:)
          reply = format ? FORMAT_REPLY_TOKENS : REPLY_TOKENS
          wanted = rows.sum { |row| row[:content].size } / CHARS_PER_TOKEN + reply
          ceiling = ollama_setting("max_num_ctx", 16_384).to_i
          options = { num_ctx: (wanted.fdiv(CTX_STEP).ceil * CTX_STEP).clamp(MIN_NUM_CTX, [ceiling, MIN_NUM_CTX].max) }
          options[:temperature] = format ? 0 : temperature unless format.nil? && temperature.nil?
          options[:num_predict] = FORMAT_REPLY_TOKENS if format
          options
        end

        def ollama_setting(key, default) = LLMDispatcher.ollama_settings.fetch(key, default)

        def ollama_messages(messages, sys)
          system = sys.to_s
          rows = messages.map { |entry| { role: entry[:role].to_s, content: entry[:content].to_s } }
          system.empty? ? rows : [{ role: "system", content: system }] + rows
        end

        # OpenAI-compatible clients spell the same daemon with a /v1 suffix, and
        # embeddings.rb and the router already read past it to the host root.
        # Kept here, /api/chat became /v1/api/chat and every call read as a
        # missing model.
        def ollama_base_url
          url = ENV["OLLAMA_BASE_URL"].to_s.strip
          url.empty? ? DEFAULT_BASE_URL : url.chomp("/").delete_suffix("/v1")
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
          return Result.err("ollama has no model #{model}: #{detail}", category: :model_missing) if response.code == "404"
          return Result.err("ollama #{response.code}: #{detail}", category: :rate_limit) if response.code == "429"
          # Any other 4xx is the request, not the server, so a retry repeats it.
          return Result.err("ollama #{response.code}: #{detail}", category: :validation) if response.code.start_with?("4")

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
          tokens = [0, 0]
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

        # [prompt, reply], as Ollama counts them.
        #
        # eval_duration is left unread, so no tokens-per-second figure is kept.
        # Nothing would rank by it: the local lane leads with the largest model
        # the machine holds (ModelRouter#local_models), and the pulled models
        # that lane offers mostly carry no models.yml row whose speed score a
        # measurement could replace. A throughput figure would argue for the
        # smallest model, which is the one that loses the fold.
        def ollama_tokens(parsed)
          [parsed["prompt_eval_count"].to_i, parsed["eval_count"].to_i]
        end

        # The reply's own count is the out figure; the prompt's was reported as
        # part of it, so a 600-token answer read as 1,900 tokens out.
        def record_local_usage(model, counts)
          tokens_in, tokens_out = counts
          tokens = tokens_in + tokens_out
          return unless @session && tokens.positive?

          @session.record_cost(0.0, model:, tokens:)
          publish_llm_cost(model:, cost: 0.0, tokens:, tokens_in:, tokens_out:)
        rescue StandardError => e
          @bus&.publish("cost:record_error", error: e.message)
        end
      end
    end
  end
end
