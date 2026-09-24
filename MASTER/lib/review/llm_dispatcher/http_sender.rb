# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Review
    class LLMDispatcher
      # Two lanes RubyLLM has no provider for, each one POST away: an
      # OpenAI-compatible server on this machine (mistral.rs, LM Studio,
      # llama-server) and Replicate's hosted language models.
      module HttpSender
        LOCAL_SERVER_TIMEOUT_S = 300
        OPEN_TIMEOUT_S = 5
        REPLICATE_API = "https://api.replicate.com/v1"
        REPLICATE_WAIT_S = 60
        REPLICATE_MAX_POLLS = 240
        REPLICATE_MAX_TOKENS = 4096

        private

        def local_server_model?(model_id) = model_id.to_s.start_with?("local:")

        def replicate_chat_model?(model_id) = model_id.to_s.start_with?("replicate:")

        # The router found which server listed the model; the call goes there.
        def send_local_server(selected_model, messages, sys:, temperature: nil)
          base = @model_router&.local_server_for(selected_model)
          return Result.err("no local server lists #{selected_model}", category: :model_missing) unless base

          openai_chat(base, selected_model.delete_prefix("local:"), messages, sys:, temperature:, lane: "local server")
        end

        # A hosted OpenAI-compatible endpoint the router listed in models.yml
        # openai_compatible; the key rides along only when one is set.
        def hosted_lane?(model_id) = !@model_router&.hosted_endpoint_for(model_id).nil?

        def send_hosted(selected_model, messages, sys:, temperature: nil)
          endpoint = @model_router.hosted_endpoint_for(selected_model)
          name, model = selected_model.split(":", 2)
          headers = endpoint[:key] ? { "Authorization" => "Bearer #{endpoint[:key]}" } : {}
          openai_chat(endpoint[:base], model, messages, sys:, temperature:, headers:, lane: name)
        end

        def openai_chat(base, model, messages, sys:, temperature:, lane:, headers: {})
          body = { model:, messages: ollama_messages(messages, sys), stream: false }
          body[:temperature] = temperature if temperature
          response = post_json("#{base.chomp('/')}/chat/completions", body, headers:, timeout: LOCAL_SERVER_TIMEOUT_S)
          return http_lane_error(lane, response) unless response.is_a?(Net::HTTPSuccess)

          Result.ok(JSON.parse(response.body).dig("choices", 0, "message", "content").to_s)
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          Result.err("#{lane} unreachable at #{base}: #{e.message}", category: :provider_error)
        end

        # Replicate answers inside the wait window or hands back a prediction to
        # poll; either way the output is the reply's tokens as an array.
        def send_replicate_chat(selected_model, messages, sys:)
          slug = selected_model.delete_prefix("replicate:")
          input = { prompt: text_prompt_for(messages), max_tokens: REPLICATE_MAX_TOKENS }
          input[:system_prompt] = sys unless sys.to_s.empty?
          response = post_json("#{REPLICATE_API}/models/#{slug}/predictions", { input: }, headers: replicate_headers,
                                                                                         timeout: REPLICATE_WAIT_S + 10)
          return http_lane_error("replicate", response) unless response.is_a?(Net::HTTPSuccess)

          replicate_output(JSON.parse(response.body))
        end

        def replicate_output(prediction)
          REPLICATE_MAX_POLLS.times do
            return Result.ok(Array(prediction["output"]).join) if prediction["status"] == "succeeded"
            if %w[failed canceled].include?(prediction["status"])
              return Result.err("replicate: #{prediction['error'] || prediction['status']}", category: :provider_error)
            end

            sleep 1
            prediction = JSON.parse(Net::HTTP.get(URI(prediction.dig("urls", "get")), replicate_headers))
          end
          Result.err("replicate: no answer after #{REPLICATE_MAX_POLLS} polls", category: :timeout)
        end

        def replicate_headers
          token = [ENV["REPLICATE_API_TOKEN"], ENV["REPLICATE_API_KEY"]].map(&:to_s).find { |key| !key.empty? }
          { "Authorization" => "Bearer #{token}", "Prefer" => "wait=#{REPLICATE_WAIT_S}" }
        end

        def post_json(url, body, headers: {}, timeout: LOCAL_SERVER_TIMEOUT_S)
          uri = URI(url)
          request = Net::HTTP::Post.new(uri.request_uri, headers.merge("Content-Type" => "application/json"))
          request.body = JSON.generate(body)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: OPEN_TIMEOUT_S, read_timeout: timeout) do |http|
            http.request(request)
          end
        end

        # A refused key, a spent balance and a busy host are three different
        # moves for the chain, so each gets the category that makes it.
        def http_lane_error(lane, response)
          said = "#{lane} #{response.code}: #{response.body.to_s[0, 300]}"
          category = { "401" => :no_api_key, "402" => :budget, "404" => :model_missing, "429" => :rate_limit }
                     .fetch(response.code) { response.code.start_with?("4") ? :validation : :provider_error }
          Result.err(said, category:)
        end
      end
    end
  end
end
