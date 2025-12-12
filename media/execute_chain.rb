#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "fileutils"

# Execute Cinematic Chain - ra2 LoRA to Video
# Simple, working implementation

TOKEN = ENV["REPLICATE_API_TOKEN"]

def api_post(path, body)
  uri = URI("https://api.replicate.com/v1#{path}")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Token #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json
  
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
end

def api_get(path)
  uri = URI("https://api.replicate.com/v1#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Token #{TOKEN}"
  
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
end

def wait_for(prediction_id, name)
  puts "⏳ Waiting for #{name}..."
  
  loop do
    sleep 5
    res = api_get("/predictions/#{prediction_id}")
    data = JSON.parse(res.body)
    
    case data["status"]
    when "succeeded"
      puts "✓ #{name} complete!"
      return data
    when "failed"
      puts "✗ #{name} failed: #{data["error"]}"
      return nil
    else
      print "."
    end
  end
end

# Step 1: Generate with ra2 LoRA
puts "\n" + "="*70
puts "CINEMATIC CHAIN: RA2 LORA → VIDEO"
puts "="*70

prompt = ARGV[0] || "beautiful cinematic portrait, golden hour lighting, shallow depth of field, professional photography, warm tones, 85mm lens"

puts "\n1. GENERATING IMAGE WITH RA2 LORA"
puts "   Prompt: #{prompt[0..80]}..."

res = api_post("/predictions", {
  version: "anon987654321/ra2:latest",
  input: {
    prompt: prompt,
    aspect_ratio: "16:9",
    output_format: "webp",
    num_inference_steps: 50
  }
})

data = JSON.parse(res.body)
if res.code != "201"
  puts "Error: #{data["detail"]}"
  exit 1
end

result = wait_for(data["id"], "ra2 image generation")
exit 1 unless result

image_url = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
puts "   Image: #{image_url}"

# Download image
puts "\n2. DOWNLOADING IMAGE"
image_data = Net::HTTP.get(URI(image_url))
FileUtils.mkdir_p("outputs")
File.write("outputs/ra2_image.webp", image_data)
puts "   ✓ Saved to outputs/ra2_image.webp"

# Step 2: Find available image-to-video model
puts "\n3. SEARCHING FOR IMAGE-TO-VIDEO MODELS"
res = api_get("/collections/image-to-video")
coll_data = JSON.parse(res.body)
models = coll_data["models"] || []

video_model = models.find { |m| m["run_count"] && m["run_count"] > 1000 }
if video_model
  model_id = "#{video_model["owner"]}/#{video_model["name"]}"
  puts "   Using: #{model_id}"
  puts "   (#{video_model["run_count"]} runs)"
  
  # Step 3: Generate video
  puts "\n4. GENERATING VIDEO"
  
  res = api_post("/predictions", {
    version: video_model["latest_version"]["id"],
    input: {
      image: image_url,
      prompt: prompt
    }
  })
  
  data = JSON.parse(res.body)
  if res.code == "201"
    result = wait_for(data["id"], "video generation")
    
    if result
      video_url = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
      puts "   Video: #{video_url}"
      
      # Download video
      puts "\n5. DOWNLOADING VIDEO"
      video_data = Net::HTTP.get(URI(video_url))
      File.write("outputs/ra2_video.mp4", video_data)
      puts "   ✓ Saved to outputs/ra2_video.mp4"
      
      puts "\n" + "="*70
      puts "🎉 SUCCESS! CINEMATIC VIDEO CREATED!"
      puts "="*70
      puts "Image: outputs/ra2_image.webp"
      puts "Video: outputs/ra2_video.mp4"
      puts "="*70
    end
  else
    puts "   Error: #{data["detail"]}"
  end
else
  puts "   No suitable video models found"
  puts "   Image saved: outputs/ra2_image.webp"
end
