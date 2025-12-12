#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "fileutils"

# Repligen 9.0 - Cinematic AI Orchestrator (December 2025)
# Complete rebuild with latest models and tty-prompt integration

VERSION = "9.0.0"

# Latest Model Database (December 2025)
MODELS = {
  # LLM Orchestrator (FREE!)
  llama_70b: {
    id: "meta/llama-3.3-70b-instruct",
    cost: 0.0,
    type: :llm,
    description: "Prompt enhancement & orchestration"
  },

  # Image Generation (Latest)
  flux2_pro: {
    id: "black-forest-labs/flux-2-pro",
    cost: 0.04,
    type: :image,
    description: "4K, best text rendering, photorealistic"
  },
  
  flux2_dev: {
    id: "black-forest-labs/flux-2-dev",
    cost: 0.01,
    type: :image,
    description: "Fast, open-weight"
  },

  ra2_lora: {
    id: "anon987654321/ra2",
    cost: 0.02,
    type: :image,
    description: "Custom LoRA (girlfriend portrait)"
  },

  # Video Generation (Cinematic)
  veo: {
    id: "google-deepmind/veo",
    cost: 0.80,
    type: :video,
    description: "Google Veo 3.1 - best cinematic, native audio, 60s"
  },

  runway: {
    id: "runway/gen-4-5",
    cost: 0.60,
    type: :video,
    description: "Runway Gen-4.5 - industry standard, realistic physics"
  },

  kling: {
    id: "kuaishou/kling-2-6",
    cost: 0.50,
    type: :video,
    description: "Kling 2.6 - simultaneous audio-visual, 1080p"
  },

  luma: {
    id: "luma/ray-2",
    cost: 0.30,
    type: :video,
    description: "Luma Ray 2 - fast, 9s clips, style transfer"
  }
}

class Repligen
  attr_reader :token, :prompt

  def initialize
    @token = ENV["REPLICATE_API_TOKEN"]
    @prompt = nil
    setup_tty_prompt
  end

  def setup_tty_prompt
    require "tty-prompt"
    @prompt = TTY::Prompt.new(
      prefix: "🎬",
      active_color: :cyan,
      help_color: :bright_black
    )
  rescue LoadError
    puts "[repligen] Installing tty-prompt..."
    system("gem install tty-prompt --no-document")
    require "tty-prompt"
    @prompt = TTY::Prompt.new(prefix: "🎬")
  end

  def api_request(method, path, body = nil)
    uri = URI("https://api.replicate.com/v1#{path}")
    req = case method
          when :get then Net::HTTP::Get.new(uri)
          when :post then Net::HTTP::Post.new(uri)
          end
    
    req["Authorization"] = "Token #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  end

  def wait_for_prediction(prediction_id, model_name = "model")
    puts "\n⏳ Generating with #{model_name}..."
    
    loop do
      sleep 3
      res = api_request(:get, "/predictions/#{prediction_id}")
      data = JSON.parse(res.body)
      
      status = data["status"]
      
      case status
      when "succeeded"
        puts "✓ Complete!"
        return data
      when "failed"
        puts "✗ Failed: #{data["error"]}"
        return nil
      when "processing"
        if data["logs"]
          last_log = data["logs"].split("\n").last
          print "\r#{last_log[0..60]}..." if last_log
        else
          print "."
        end
      else
        print "."
      end
    end
  end

  def enhance_prompt_with_llama(user_prompt, context = "cinematic portrait")
    puts "\n🤖 Enhancing prompt with Llama 3.3 70B..."
    
    system_prompt = <<~PROMPT
      You are a professional cinematographer and photographer. 
      Enhance the user's prompt for #{context} with:
      - Professional camera terminology (85mm, f/1.4, etc.)
      - Lighting direction (golden hour, soft light, etc.)
      - Composition details (rule of thirds, shallow DOF)
      - Cinematic qualities (film grain, color grading)
      - Mood and atmosphere
      
      Keep it under 150 words. Be specific and visual.
      Return ONLY the enhanced prompt, no explanation.
    PROMPT

    body = {
      input: {
        prompt: "#{system_prompt}\n\nUser prompt: #{user_prompt}\n\nEnhanced prompt:"
      }
    }

    res = api_request(:post, "/models/meta/llama-3.3-70b-instruct/predictions", body)
    data = JSON.parse(res.body)
    
    result = wait_for_prediction(data["id"], "Llama 3.3")
    return user_prompt unless result

    enhanced = result["output"].is_a?(Array) ? result["output"].join : result["output"]
    enhanced = enhanced.strip
    
    puts "\n📝 Enhanced: #{enhanced[0..100]}..."
    enhanced
  end

  def generate_image(prompt, model: :ra2_lora)
    model_info = MODELS[model]
    puts "\n🎨 Generating image with #{model_info[:description]}..."
    
    body = case model
           when :ra2_lora
             {
               input: {
                 prompt: prompt,
                 aspect_ratio: "16:9",
                 output_format: "webp",
                 num_inference_steps: 50
               }
             }
           else
             {
               input: {
                 prompt: prompt,
                 aspect_ratio: "16:9"
               }
             }
           end

    res = api_request(:post, "/models/#{model_info[:id]}/predictions", body)
    data = JSON.parse(res.body)
    
    if res.code != "201"
      puts "✗ Error: #{data["detail"]}"
      return nil
    end

    result = wait_for_prediction(data["id"], model_info[:description])
    return nil unless result

    image_url = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
    puts "✓ Image: #{image_url}"
    
    { url: image_url, cost: model_info[:cost] }
  end

  def generate_video(image_url, prompt, model: :kling)
    model_info = MODELS[model]
    puts "\n🎬 Generating video with #{model_info[:description]}..."
    
    body = {
      input: {
        image: image_url,
        prompt: prompt
      }
    }

    res = api_request(:post, "/models/#{model_info[:id]}/predictions", body)
    data = JSON.parse(res.body)
    
    if res.code != "201"
      puts "✗ Error: #{data["detail"]}"
      return nil
    end

    result = wait_for_prediction(data["id"], model_info[:description])
    return nil unless result

    video_url = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
    puts "✓ Video: #{video_url}"
    
    { url: video_url, cost: model_info[:cost] }
  end

  def cinematic_workflow(user_prompt)
    puts "\n" + "="*70
    puts "REPLIGEN #{VERSION} - CINEMATIC AI ORCHESTRATOR"
    puts "="*70

    # Step 1: Enhance prompt with Llama 3.3
    enhanced_prompt = enhance_prompt_with_llama(user_prompt)

    # Step 2: Choose image model
    image_model = @prompt.select("Choose image generator:", %w[ra2_lora flux2_pro flux2_dev].map(&:to_sym))

    # Step 3: Generate image
    image_result = generate_image(enhanced_prompt, model: image_model)
    return unless image_result

    # Step 4: Choose video model
    video_model = @prompt.select("Choose video generator:", %w[kling luma veo runway].map(&:to_sym))

    # Step 5: Generate video
    video_result = generate_video(image_result[:url], enhanced_prompt, model: video_model)
    return unless video_result

    # Summary
    total_cost = image_result[:cost] + video_result[:cost]
    
    puts "\n" + "="*70
    puts "🎉 CINEMATIC WORKFLOW COMPLETE!"
    puts "="*70
    puts "Image: #{image_result[:url]}"
    puts "Video: #{video_result[:url]}"
    puts "Total cost: $#{total_cost.round(2)}"
    puts "\nDownload with:"
    puts "  curl -o video.mp4 '#{video_result[:url]}'"
    puts "="*70
  end

  def interactive_cli
    unless @token
      puts "Error: Set REPLICATE_API_TOKEN environment variable"
      exit 1
    end

    loop do
      choice = @prompt.select("What would you like to do?", [
        "Cinematic Portrait (ra2 LoRA → video)",
        "Quick Image (Flux 2 Pro)",
        "View Models",
        "Exit"
      ])

      case choice
      when /Cinematic/
        prompt = @prompt.ask("Describe your vision:")
        cinematic_workflow(prompt) if prompt && !prompt.empty?
      when /Quick/
        prompt = @prompt.ask("Image prompt:")
        generate_image(prompt, model: :flux2_pro) if prompt && !prompt.empty?
      when /Models/
        puts "\nAvailable Models:"
        MODELS.each do |key, info|
          puts "  #{key}: #{info[:description]} ($#{info[:cost]})"
        end
        puts "\nPress Enter to continue"
        gets
      when /Exit/
        puts "Goodbye!"
        break
      end
    end
  end

  def run(args)
    if args.empty?
      interactive_cli
    else
      command = args[0]
      case command
      when "cinematic", "c"
        prompt = args[1..-1].join(" ")
        cinematic_workflow(prompt)
      else
        puts "Usage: repligen.rb [cinematic 'prompt']"
        puts "   or: repligen.rb    (interactive mode)"
      end
    end
  end
end

if __FILE__ == $0
  repligen = Repligen.new
  repligen.run(ARGV)
end
