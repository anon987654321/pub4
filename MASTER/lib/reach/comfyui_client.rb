# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"

module Master
  module Reach
    # ComfyUI API client for self-hosted AnimateDiff I2V (Flux keyframe → motion LoRA clip).
    class ComfyuiClient
      DEFAULT_URL = "http://127.0.0.1:8188"
      WORKFLOW_NAME = "animatediff_i2v.workflow.json"
      INPUTS_NAME = "animatediff_i2v.inputs.yml"
      POLL_INTERVAL = 3
      DEFAULT_TIMEOUT = 900

      def initialize(base_url: nil, workflow_path: nil, inputs_map_path: nil, client_id: nil, wrapper_url: nil)
        @base_url = (base_url || ENV["COMFYUI_URL"] || DEFAULT_URL).to_s.delete_suffix("/")
        @wrapper_url = (wrapper_url || ENV["COMFYUI_WRAPPER_URL"]).to_s.delete_suffix("/")
        @workflow_path = workflow_path || default_workflow_path
        @inputs_map_path = inputs_map_path || default_inputs_path
        @client_id = client_id || SecureRandom.uuid
      end

      def i2v(keyframe_url:, prompt:, frames: 24, motion_lora: nil, motion_weight: 0.75,
             motion_lora_2: nil, motion_lora_2_weight: nil, timeout: DEFAULT_TIMEOUT)
        return i2v_via_wrapper(
          keyframe_url: keyframe_url,
          prompt: prompt,
          frames: frames,
          motion_lora: motion_lora,
          motion_weight: motion_weight,
          motion_lora_2: motion_lora_2,
          motion_lora_2_weight: motion_lora_2_weight,
          timeout: timeout
        ) unless @wrapper_url.empty?

        workflow = load_workflow
        image_name = ingest_keyframe(keyframe_url)
        patch_workflow!(
          workflow,
          image: image_name,
          prompt: prompt,
          frame_count: frames,
          motion_lora: motion_lora,
          motion_lora_strength: motion_weight,
          motion_lora_2: motion_lora_2,
          motion_lora_2_strength: motion_lora_2_weight
        )
        prompt_id = queue_prompt(workflow)
        history = wait_for_history(prompt_id, timeout: timeout)
        video_ref = extract_video_ref(history)
        resolve_output_url(video_ref)
      end

      private

      def i2v_via_wrapper(keyframe_url:, prompt:, frames:, motion_lora:, motion_weight:,
                          motion_lora_2:, motion_lora_2_weight:, timeout:)
        motion_loras = [motion_lora, motion_lora_2].compact.reject(&:empty?)
        payload = {
          prompt: prompt,
          image: keyframe_url,
          frame_count: frames,
          motion_loras: motion_loras,
          motion_lora_strength: motion_weight,
          motion_lora_2_strength: motion_lora_2_weight,
          duration: (frames / 8.0).ceil,
        }
        uri = URI("#{@wrapper_url}/api/animatediff/generate")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
        data = request_json(req, uri, read_timeout: timeout)
        data["view_url"] || data["output_url"] || raise(VideoChain::Error, "wrapper missing output URL")
      end

      def default_workflow_path = Master.data_path("comfyui", WORKFLOW_NAME)
      def default_inputs_path = Master.data_path("comfyui", INPUTS_NAME)

      def load_workflow
        raise VideoChain::Error, "missing ComfyUI workflow: #{@workflow_path}" unless File.file?(@workflow_path)

        JSON.parse(File.read(@workflow_path))
      end

      def load_inputs_map
        raise VideoChain::Error, "missing ComfyUI inputs map: #{@inputs_map_path}" unless File.file?(@inputs_map_path)

        data = Master.load_yaml(@inputs_map_path) || {}
        data.transform_keys(&:to_sym)
      end

      def patch_workflow!(workflow, values)
        map = load_inputs_map
        map.each do |key, path|
          value = values[key]
          next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

          set_node_input!(workflow, path, value)
        end
      end

      def set_node_input!(workflow, path, value)
        node_id, field = path.to_s.split(".inputs.", 2)
        raise VideoChain::Error, "bad inputs map path: #{path}" if field.nil? || node_id.empty?

        node = workflow[node_id] || workflow.dig("prompt", node_id)
        raise VideoChain::Error, "workflow missing node #{node_id}" unless node

        node["inputs"] ||= {}
        node["inputs"][field] = value
      end

      def ingest_keyframe(keyframe_url)
        uri = URI(keyframe_url.to_s)
        return upload_image(keyframe_url) unless uri.scheme&.match?(/\Ahttps?\z/)

        temp = File.join(Dir.tmpdir, "video_chain_keyframe_#{SecureRandom.hex(6)}.png")
        VideoPost.download_url(keyframe_url, temp)
        upload_image(temp)
      ensure
        File.delete(temp) if defined?(temp) && temp && File.exist?(temp)
      end

      def upload_image(path)
        boundary = "ComfyUIBoundary#{rand(1_000_000_000)}"
        body = "--#{boundary}\r\n".b +
               "Content-Disposition: form-data; name=\"image\"; filename=\"#{File.basename(path)}\"\r\n".b +
               "Content-Type: image/png\r\n\r\n".b +
               File.binread(path) +
               "\r\n--#{boundary}--\r\n".b
        uri = URI("#{@base_url}/upload/image")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = body
        data = request_json(req, uri)
        data["name"] || raise(VideoChain::Error, "ComfyUI upload missing filename")
      end

      def queue_prompt(workflow)
        uri = URI("#{@base_url}/prompt")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate({ prompt: workflow, client_id: @client_id })
        data = request_json(req, uri)
        data["prompt_id"] || raise(VideoChain::Error, "ComfyUI queue missing prompt_id")
      end

      def wait_for_history(prompt_id, timeout:)
        start = Time.now
        loop do
          uri = URI("#{@base_url}/history/#{prompt_id}")
          data = request_json(Net::HTTP::Get.new(uri), uri)
          entry = data[prompt_id]
          return entry if entry && entry["outputs"]

          raise VideoChain::Error, "ComfyUI timeout after #{timeout}s" if Time.now - start > timeout
          sleep POLL_INTERVAL
        end
      end

      def extract_video_ref(history)
        outputs = history["outputs"] || {}
        outputs.each_value do |node|
          Array(node["gifs"]).each { |item| return item if item["filename"] }
          Array(node["videos"]).each { |item| return item if item["filename"] }
          Array(node["images"]).each do |item|
            return item if item["filename"] && item["filename"].to_s.match?(/\.(mp4|webm|gif)\z/i)
          end
        end
        raise VideoChain::Error, "ComfyUI history contained no video output"
      end

      def resolve_output_url(ref)
        params = {
          filename: ref["filename"],
          subfolder: ref["subfolder"].to_s,
          type: ref["type"] || "output",
        }
        "#{@base_url}/view?#{URI.encode_www_form(params)}"
      end

      def request_json(req, uri, read_timeout: 120)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: read_timeout) do |http|
          http.request(req)
        end
        raise VideoChain::Error, "ComfyUI #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      rescue JSON::ParserError => e
        raise VideoChain::Error, "ComfyUI invalid JSON: #{e.message}"
      end
    end
  end
end
