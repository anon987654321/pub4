# frozen_string_literal: true
require "net/http"
require "json"
require "uri"
require "fileutils"

module Master
  module Replicate
    BASE_URL = "https://api.replicate.com/v1"
    OUTPUT_DIR = File.join(Master::ROOT, "var", "replicate")
    
    MODELS = {
      # Image generation
      flux: "black-forest-labs/flux-1.1-pro",
      sdxl: "stability-ai/sdxl",
      
      # Image editing
      inpaint: "stability-ai/stable-diffusion-inpainting",
      upscale: "nightmareai/real-esrgan",
      remove_bg: "cjwbw/rembg",
      
      # Video
      video: "anotherjesse/zeroscope-v2-xl",
      
      # Audio
      whisper: "openai/whisper",
      musicgen: "meta/musicgen",
      
      # Vision
      llava: "yorickvp/llava-13b",
      blip: "salesforce/blip"
    }.freeze

    class << self
      def api_key
        ENV["REPLICATE_API_TOKEN"]
      end

      def available?
        !api_key.nil?
      end

      def generate_image(prompt, model: :flux)
        return Result.err("No Replicate API key") unless available?
        
        model_id = MODELS[model] || MODELS[:flux]
        
        result = run_model(model_id, { prompt: prompt })
        return result unless result.ok?
        
        output = result.value
        if output.is_a?(Array) && output.first
          download_file(output.first, "image")
        else
          Result.ok(output)
        end
      end

      def describe_image(image_path, question: "What is in this image?")
        return Result.err("No Replicate API key") unless available?
        return Result.err("File not found: #{image_path}") unless File.exist?(image_path)
        
        # Upload image and get URL (or use base64)
        image_data = Base64.strict_encode64(File.read(image_path, mode: "rb"))
        image_url = "data:image/png;base64,#{image_data}"
        
        run_model(MODELS[:llava], {
          image: image_url,
          prompt: question
        })
      end

      def transcribe(audio_path)
        return Result.err("No Replicate API key") unless available?
        return Result.err("File not found: #{audio_path}") unless File.exist?(audio_path)
        
        # For whisper, need to upload file
        run_model(MODELS[:whisper], {
          audio: audio_path
        })
      end

      def generate_music(prompt, duration: 10)
        return Result.err("No Replicate API key") unless available?
        
        result = run_model(MODELS[:musicgen], {
          prompt: prompt,
          duration: duration
        })
        return result unless result.ok?
        
        output = result.value
        if output.is_a?(String) && output.start_with?("http")
          download_file(output, "audio")
        else
          Result.ok(output)
        end
      end

      def upscale(image_path, scale: 4)
        return Result.err("No Replicate API key") unless available?
        return Result.err("File not found: #{image_path}") unless File.exist?(image_path)
        
        image_data = Base64.strict_encode64(File.read(image_path, mode: "rb"))
        image_url = "data:image/png;base64,#{image_data}"
        
        result = run_model(MODELS[:upscale], {
          image: image_url,
          scale: scale
        })
        return result unless result.ok?
        
        download_file(result.value, "upscaled")
      end

      def remove_background(image_path)
        return Result.err("No Replicate API key") unless available?
        return Result.err("File not found: #{image_path}") unless File.exist?(image_path)
        
        image_data = Base64.strict_encode64(File.read(image_path, mode: "rb"))
        image_url = "data:image/png;base64,#{image_data}"
        
        result = run_model(MODELS[:remove_bg], { image: image_url })
        return result unless result.ok?
        
        download_file(result.value, "nobg")
      end

      private

      def run_model(model_id, input)
        uri = URI("#{BASE_URL}/predictions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 300
        
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{api_key}"
        req["Content-Type"] = "application/json"
        req.body = { version: model_id, input: input }.to_json
        
        resp = http.request(req)
        data = JSON.parse(resp.body)
        
        return Result.err(data["detail"] || "Failed to start") unless data["id"]
        
        # Poll for completion
        poll_prediction(data["id"])
      rescue => e
        Result.err("Replicate error: #{e.message}")
      end

      def poll_prediction(id, max_wait: 300)
        uri = URI("#{BASE_URL}/predictions/#{id}")
        start = Time.now
        
        loop do
          return Result.err("Timeout waiting for result") if Time.now - start > max_wait
          
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          req = Net::HTTP::Get.new(uri)
          req["Authorization"] = "Bearer #{api_key}"
          
          resp = http.request(req)
          data = JSON.parse(resp.body)
          
          case data["status"]
          when "succeeded"
            return Result.ok(data["output"])
          when "failed", "canceled"
            return Result.err(data["error"] || "Prediction failed")
          end
          
          sleep 2
        end
      end

      def download_file(url, prefix)
        FileUtils.mkdir_p(OUTPUT_DIR)
        
        uri = URI(url)
        ext = File.extname(uri.path).empty? ? ".png" : File.extname(uri.path)
        filename = "#{prefix}_#{Time.now.to_i}#{ext}"
        path = File.join(OUTPUT_DIR, filename)
        
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        resp = http.get(uri.path)
        
        File.write(path, resp.body, mode: "wb")
        Result.ok(path)
      rescue => e
        Result.err("Download failed: #{e.message}")
      end
    end
  end
end
