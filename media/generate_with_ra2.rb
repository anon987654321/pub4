#!/usr/bin/env ruby
require "net/http"
require "json"
require "uri"

TOKEN = ENV["REPLICATE_API_TOKEN"]

unless TOKEN
  puts "Error: Set REPLICATE_API_TOKEN"
  exit 1
end

def api_request(method, path, body = nil)
  uri = URI("https://api.replicate.com/v1#{path}")
  req = case method
        when :get then Net::HTTP::Get.new(uri)
        when :post then Net::HTTP::Post.new(uri)
        end
  
  req["Authorization"] = "Token #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json if body
  
  Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
end

def wait_for_prediction(prediction_id)
  loop do
    sleep 3
    res = api_request(:get, "/predictions/#{prediction_id}")
    data = JSON.parse(res.body)
    
    status = data["status"]
    print "."
    
    return data if status == "succeeded"
    
    if status == "failed"
      puts "\n✗ Failed: #{data["error"]}"
      return nil
    end
  end
end

# Step 1: Generate image with RA2 LoRA
puts "=== GENERATING IMAGE WITH RA2 LORA ==="
prompt = ARGV[0] || "beautiful cinematic portrait, professional photography, warm lighting"

body = {
  input: {
    prompt: prompt,
    aspect_ratio: "16:9",
    output_format: "webp",
    num_inference_steps: 50
  }
}

res = api_request(:post, "/models/anon987654321/ra2/predictions", body)
data = JSON.parse(res.body)

if res.code != "201"
  puts "Error: #{data["detail"]}"
  exit 1
end

puts "Prediction: #{data["id"]}"
result = wait_for_prediction(data["id"])

if result
  image_url = result["output"].is_a?(Array) ? result["output"][0] : result["output"]
  puts "\n✓ Image: #{image_url}"
  puts "\nTo generate video from this image, we need to select a video model."
  puts "Check https://replicate.com/collections/image-to-video for options"
else
  exit 1
end
