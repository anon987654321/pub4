# frozen_string_literal: true

require "json"
require "uri"
require "net/http"
require_relative "../result"

module MASTER
  module Replicate
    # Client - HTTP + text-generation for the Replicate API.
    # Combines low-level HTTP (create_prediction/wait_for_completion) with the
    # model-family-aware `complete` entrypoint previously in Replicate::LLM.
    # Media callers (Replicate::Media, Narration, Generators) use create_prediction /
    # wait_for_completion directly; LLM.ask uses Client.complete.
    module Client
      API_URL        = "https://api.replicate.com/v1/predictions"
      MODELS_API_URL = "https://api.replicate.com/v1/models"

      HTTP_OPEN_TIMEOUT  = (ENV["MASTER_HTTP_OPEN_TIMEOUT"]  || 10).to_i
      HTTP_READ_TIMEOUT  = (ENV["MASTER_HTTP_READ_TIMEOUT"]  || 60).to_i
      REPLICATE_TIMEOUT  = (ENV["MASTER_REPLICATE_TIMEOUT"]  || 300).to_i
      POLL_INTERVAL      = (ENV["MASTER_POLL_INTERVAL"]      || 2).to_i

      DEFAULT_MAX_TOKENS  = 4_096
      DEFAULT_TEMPERATURE = 0.6
      DEFAULT_TOP_P       = 0.95

      module_function

      # Text-generation entry point (was Replicate::LLM.complete).
      # Builds model-family-aware input, creates a prediction, polls until done.
      def complete(model_id, prompt, system_prompt: nil, max_tokens: DEFAULT_MAX_TOKENS,
                   temperature: DEFAULT_TEMPERATURE, top_p: DEFAULT_TOP_P, **_opts)
        input = build_llm_input(model_id, prompt, system_prompt, max_tokens, temperature, top_p)

        prediction = create_prediction(model: model_id, input: input)
        return Result.err("Replicate prediction failed: #{prediction[:error]}", category: :infrastructure) if prediction[:error]

        completion = wait_for_completion(prediction[:id])
        return Result.err("Replicate completion failed: #{completion[:error]}", category: :infrastructure) if completion[:error]

        content = Array(completion[:output]).join
        return Result.err("Empty response from #{model_id.split('/').last}") if content.strip.empty?

        Result.ok(
          content: content,
          model: model_id,
          provider: :replicate,
          tokens_in: 0,
          tokens_out: 0,
          cost: nil,
          finish_reason: "stop",
        )
      rescue StandardError => err
        Result.err("Replicate LLM error: #{err.message}", category: :infrastructure)
      end


      # Create a new prediction
      def create_prediction(model:, input:)
        body = { input: input }
        # Official models (owner/name) use /v1/models/{owner}/{name}/predictions
        # Version-pinned models use /v1/predictions with a version SHA
        if model&.include?("/") && !model.match?(/[0-9a-f]{40,}/)
          owner, name = model.split("/", 2)
          url = "#{MODELS_API_URL}/#{owner}/#{name}/predictions"
        elsif model
          body[:version] = model
          url = API_URL
        end

        data = http_post(url, body)
        if data&.dig(:id)
          { id: data[:id] }
        else
          { error: data&.dig(:detail) || "Unknown error" }
        end
      rescue StandardError => err
        warn "Replicate: create_prediction error: #{err.class} - #{err.message}"
        { error: err.message }
      end

      # Wait for prediction to complete (polling loop)
      def wait_for_completion(id, timeout: REPLICATE_TIMEOUT)
        poll_url = "#{API_URL}/#{id}"
        start_time = Time.now

        loop do
          return { error: "Timeout waiting for generation" } if Time.now - start_time > timeout

          data = http_get(poll_url)

          case data&.dig(:status)
          when "succeeded"
            return { id: id, output: data[:output] }
          when "failed", "canceled"
            return { error: data[:error] || "Generation failed" }
          when "processing", "starting", "queued"
            sleep POLL_INTERVAL
          else
            return { error: "Unknown status: #{data&.dig(:status) || 'nil'}" }
          end
        end
      rescue StandardError => err
        warn "Replicate: wait_for_completion error: #{err.class} - #{err.message}"
        { error: err.message }
      end

      # Download file from URL to local path
      def download_file(url, path)
        uri = URI(url)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                                           open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT) do |http|
          http.get(uri.request_uri)
        end
        return false unless response.is_a?(Net::HTTPSuccess)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, response.body)
        true
      rescue StandardError => err
        warn "Replicate: download_file failed for #{url}: #{err.message}"
        false
      end

      def http_post(url, body)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{Replicate.api_key}"
        req["Content-Type"]  = "application/json"
        req.body = body.to_json

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                                           open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT) do |http|
          http.request(req)
        end
        JSON.parse(response.body, symbolize_names: true)
      end

      def http_get(url)
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{Replicate.api_key}"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
                                                           open_timeout: HTTP_OPEN_TIMEOUT, read_timeout: HTTP_READ_TIMEOUT) do |http|
          http.request(req)
        end
        JSON.parse(response.body, symbolize_names: true)
      end

      # Build model-family-aware input hash.
      # anthropic/*   → prompt, system, max_tokens, temperature
      # deepseek-ai/* → prompt, system_prompt, max_tokens, temperature, top_p
      # default       → deepseek-style schema (most open LLMs on Replicate)
      def build_llm_input(model_id, prompt, system_prompt, max_tokens, temperature, top_p)
        owner = model_id.split("/").first
        case owner
        when "anthropic"
          base = { prompt: prompt, max_tokens: [max_tokens, 1024].max, temperature: temperature }
          base[:system] = system_prompt if system_prompt
          base
        when "deepseek-ai"
          base = { prompt: prompt, max_tokens: max_tokens, temperature: temperature, top_p: top_p }
          base[:system_prompt] = system_prompt if system_prompt
          base
        else
          base = { prompt: prompt, max_tokens: max_tokens, temperature: temperature, top_p: top_p }
          base[:system_prompt] = system_prompt if system_prompt
          base
        end
      end
    end
  end
end
